# GUIA ARQUITETURAL SUPABASE: SERVERLESS EDGE, MULTI-TENANCY (RLS), REALTIME & PGVECTOR
> **Stack:** Supabase (PostgreSQL) · Cloudflare Workers (Edge Clients Scoped/Admin) · React SPA (Realtime WebSocket)  
> **Classificação:** Padrões e Práticas de Integração do Supabase em Arquiteturas Serverless Edge  
> **Finalidade:** Especificação técnica e boilerplate reutilizável para modelagem relacional, isolamento multi-tenant via RLS, autenticação JWT/JWKS, Realtime de alta performance e busca semântica com pgvector.
>
> ⚠️ **Aviso de Segurança:** Nenhum dado sensível, chaves privadas ou URLs de produção reais estão presentes neste documento. Todos os valores utilizam marcadores padronizados (ex: `<PROJECT_REF>`, `<SUPABASE_ANON_KEY>`).

---

## 1. Visão Geral da Arquitetura

O Supabase é empregado como a espinha dorsal de dados e eventos em tempo real, integrando três camadas principais:

```
┌────────────────────────────────────────────────────────┐
│                   Frontend (SPA / React)               │
│  - Supabase JS Client com ANON_KEY                     │
│  - Escuta Canais Realtime via WebSocket (Broadcast)    │
│  - Invalidação reativa de cache (TanStack Query)       │
└──────────────────────────┬─────────────────────────────┘
                           │ HTTPS / JWT
                           ▼
┌────────────────────────────────────────────────────────┐
│             Backend API (Cloudflare Workers / Hono)    │
│  - Validação offline de JWT via JWKS (jose)           │
│  - Client Scoped (repassa Bearer JWT do usuário)       │
│  - Client Admin (Service Role + cabeçalho x-actor-id)  │
│  - Disparo de eventos Realtime via HTTP Broadcast REST │
└──────────────────────────┬─────────────────────────────┘
                           │ Pooling / REST / RPC
                           ▼
┌────────────────────────────────────────────────────────┐
│              Supabase Cloud / PostgreSQL               │
│  - Isolamento Multi-tenant via Row Level Security (RLS)│
│  - Triggers de auditoria automáticos                   │
│  - Busca Semântica / RAG com extensão pgvector + HNSW  │
│  - Supabase Storage com políticas de acesso e cache    │
└────────────────────────────────────────────────────────┘
```

---

## 2. Inicialização do Cliente Supabase

### 2.1. No Frontend (Client-Side)

No frontend, utiliza-se a chave pública anônima (`VITE_SUPABASE_ANON_KEY`), onde as requisições diretas ao banco são limitadas pelas políticas de RLS vinculadas à sessão do usuário autenticado.

Além disso, para aplicações com canais de Realtime contínuos, é crucial configurar a renovação do token na conexão WebSocket para evitar quedas por `Token Expired` após 1 hora:

```typescript
// src/integrations/supabase/client.ts
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || '';
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY || '';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Garante que o WebSocket do RealtimeClient sempre use o JWT mais recente do Gateway
(supabase.realtime as any).accessToken = async () => {
  return (typeof window !== 'undefined' ? localStorage.getItem('auth_token') : null) || SUPABASE_ANON_KEY;
};

let lastSyncedToken: string | null = null;

/**
 * Sincroniza o JWT de autenticação com a conexão WebSocket do Supabase Realtime.
 * Evita que o socket caia silenciosamente por "Token Expired" após 1 hora de uso contínuo.
 */
export function syncRealtimeAuth(token: string | null) {
  if (!token || token === lastSyncedToken) return;

  try {
    lastSyncedToken = token;
    supabase.realtime.setAuth(token);
    console.log('[Supabase Realtime] 🔑 Token sincronizado com o WebSocket');
  } catch (err) {
    console.error('[Supabase Realtime] Erro ao sincronizar auth token com o WebSocket:', err);
  }
}

/**
 * Disparo seguro de Broadcast pelo frontend com fallback explícito para httpSend()
 * Previne deprecation warnings da SDK do Supabase.
 */
export async function sendRealtimeBroadcast(
  target: string | any,
  event: string,
  payload: Record<string, any>
): Promise<void> {
  const channel = typeof target === 'string' ? supabase.channel(target) : target;
  if (!channel) return;

  const canPush = Boolean(channel.channelAdapter?.canPush?.() || channel.canPush?.());
  if (canPush) {
    await channel.send({ type: 'broadcast', event, payload });
  } else if (typeof channel.httpSend === 'function') {
    await channel.httpSend(event, payload);
  } else {
    await channel.send({ type: 'broadcast', event, payload });
  }
}
```

---

### 2.2. No Backend Serverless (Cloudflare Workers / Node.js)

Em ambientes serverless (stateless), a persistência de sessão em localStorage/cookies e a renovação automática de token em background devem ser **desativadas**. Além disso, o backend opera com dois tipos de cliente:

1. **Client com Escopo do Usuário (`getSupabase`):** Repassa o token JWT do usuário no cabeçalho `Authorization: Bearer <token>`. O PostgreSQL enxerga o `auth.uid()` nativamente e aplica as regras de RLS do usuário.
2. **Client Administrativo (`getSupabaseAdmin`):** Utiliza a `SUPABASE_SERVICE_ROLE_KEY` (ignora o RLS). Usado em webhooks, filas assíncronas e crons. Para manter a rastreabilidade da auditoria, propaga o usuário no cabeçalho `x-actor-id`.

```typescript
// src/lib/supabase.ts
import { createClient, SupabaseClient } from '@supabase/supabase-js';

export const createSupabaseClient = (
  url: string,
  key: string,
  accessToken?: string,
  extraHeaders?: Record<string, string>,
): SupabaseClient => {
  const options: any = {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  };

  const headers: Record<string, string> = { ...extraHeaders };
  if (accessToken) {
    headers.Authorization = `Bearer ${accessToken}`;
  }
  if (Object.keys(headers).length > 0) {
    options.global = { headers };
  }

  return createClient(url, key, options);
};

/**
 * Cliente autenticado no contexto do usuário atual.
 * Preserva as políticas de RLS e disponibiliza auth.uid() no PostgreSQL.
 */
export const getSupabase = (c: any): SupabaseClient => {
  return createSupabaseClient(
    c.env.SUPABASE_URL,
    c.env.SUPABASE_ANON_KEY,
    c.get('token'), // Extraído do middleware de autenticação
  );
};

/**
 * Cliente administrativo com Service Role Key (ignora RLS).
 * Propaga 'x-actor-id' para triggers de auditoria registrarem o autor da ação.
 */
export const getSupabaseAdmin = (c: any): SupabaseClient => {
  const user = c.get('user');
  return createSupabaseClient(
    c.env.SUPABASE_URL,
    c.env.SUPABASE_SERVICE_ROLE_KEY,
    undefined,
    user?.id ? { 'x-actor-id': user.id } : undefined,
  );
};

/**
 * Alterna dinamicamente entre admin e usuário de acordo com privilégios de superadmin.
 */
export const getEffectiveSupabase = async (c: any, userId?: string): Promise<SupabaseClient> => {
  const admin = getSupabaseAdmin(c);
  const uid = userId || c.get('user')?.id;
  if (!uid) return getSupabase(c);

  const { data: profile } = await admin
    .from('profiles')
    .select('is_superadmin')
    .eq('id', uid)
    .maybeSingle();

  return profile?.is_superadmin ? admin : getSupabase(c);
};
```

---

## 3. Autenticação e Validação Criptográfica de JWT no Backend

Para evitar chamar o endpoint `auth.getUser()` a cada requisição (o que adicionaria latência e consumiria limites de taxa da API do Supabase), o backend valida os tokens JWT **offline** utilizando chaves públicas via **JWKS** (`jose`).

```typescript
// src/middlewares/verifyJwt.ts
import { MiddlewareHandler } from 'hono';
import { jwtVerify, decodeProtectedHeader, createRemoteJWKSet } from 'jose';

const jwksCache = new Map<string, any>();

function getOrCreateJWKS(projectId: string) {
  if (!jwksCache.has(projectId)) {
    const jwks = createRemoteJWKSet(
      new URL(`https://${projectId}.supabase.co/auth/v1/.well-known/jwks.json`),
      {
        timeoutDuration: 10000,
        cacheMaxAge: 10 * 60 * 1000, // Cache de 10 minutos
      }
    );
    jwksCache.set(projectId, jwks);
  }
  return jwksCache.get(projectId);
}

export const verifyJwt: MiddlewareHandler = async (c, next) => {
  const authorization = c.req.header('Authorization');
  if (!authorization) {
    return c.json({ code: 'UNAUTHORIZED', message: 'Token ausente' }, 401);
  }

  const [prefix, token] = authorization.split(' ');
  if (!/^Bearer$/i.test(prefix) || !token) {
    return c.json({ code: 'UNAUTHORIZED', message: 'Formato de token inválido' }, 401);
  }

  const projectId = c.env.SUPABASE_PROJECT_ID || c.env.SUPABASE_URL.replace('https://', '').split('.')[0];
  const jwtSecret = c.env.SUPABASE_JWT_SECRET;

  try {
    const header = decodeProtectedHeader(token);
    let payload: any;

    if (header.alg === 'HS256' && jwtSecret) {
      // Validação simétrica
      const secret = new TextEncoder().encode(jwtSecret);
      const res = await jwtVerify(token, secret, {
        issuer: `https://${projectId}.supabase.co/auth/v1`,
      });
      payload = res.payload;
    } else {
      // Validação assimétrica via JWKS (padrão moderno Supabase)
      const JWKS = getOrCreateJWKS(projectId);
      const res = await jwtVerify(token, JWKS, {
        issuer: `https://${projectId}.supabase.co/auth/v1`,
      });
      payload = res.payload;
    }

    c.set('token', token);
    if (payload.sub) {
      c.set('user', { id: payload.sub });
    }

    return next();
  } catch (err: any) {
    return c.json({ code: 'TOKEN_INVALID', message: 'Token inválido ou expirado' }, 401);
  }
};
```

---

## 4. Multi-tenancy e Row Level Security (RLS)

O isolamento entre organizações (tenants) é garantido no próprio PostgreSQL através de RLS vinculado à tabela de permissões/membros (`memberships`).

### Exemplo de Migração SQL:

```sql
-- Ativação do RLS na tabela
alter table public.contracts enable row level security;

-- Política de leitura: o usuário só vê contratos das organizações que pertence
create policy "contracts_select_tenant_isolation"
  on public.contracts
  for select
  using (
    organization_id in (
      select m.organization_id
      from public.memberships m
      where m.profile_id = auth.uid()
    )
  );

-- Política de inserção: valida vínculo de organização
create policy "contracts_insert_tenant_isolation"
  on public.contracts
  for insert
  with check (
    organization_id in (
      select m.organization_id
      from public.memberships m
      where m.profile_id = auth.uid()
    )
  );
```

> **Regra Arquitetural:** Para tabelas internas (ex: logs, chunks de IA, filas de envio), **não se criam políticas de escrita para o usuário comum**. Apenas o backend com a `service_role` realiza as alterações, prevenindo manipulações indevidas a partir do frontend.

---

## 5. Realtime de Alta Performance: Broadcast via HTTP REST

### O Desafio
Em workers e ambientes serverless, manter conexões WebSocket persistentes abertas para emitir eventos de Realtime consome recursos desnecessários e pode estourar timeouts de execução.

### O Padrão de Solução
1. O backend emite os eventos via **HTTP Broadcast REST API** nativa do Supabase (`/realtime/v1/api/broadcast`) usando a `SUPABASE_SERVICE_ROLE_KEY`.
2. O frontend se conecta a um canal WebSocket único por organização (`customer_chat:org_<id>`) e recebe os broadcasts instantaneamente.

#### Emissor no Backend (Cloudflare Worker):

```typescript
// src/utils/realtime.ts
export async function sendHttpBroadcast(
  env: { SUPABASE_URL: string; SUPABASE_SERVICE_ROLE_KEY: string },
  topic: string,
  event: string,
  payload: any
): Promise<void> {
  const projectRef = env.SUPABASE_URL.replace('https://', '').split('.')[0];
  const url = `https://${projectRef}.supabase.co/realtime/v1/api/broadcast`;

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messages: [
          {
            topic, // Ex: "customer_chat:org_123"
            event, // Ex: "ticket_transferred"
            payload,
          },
        ],
      }),
    });

    if (!response.ok) {
      console.error(`[BROADCAST_ERROR] Status: ${response.status}`);
    }
  } catch (error) {
    console.error('[BROADCAST_CRASH]', error);
  }
}
```

#### Consumidor no Frontend (React Hook):

```typescript
// src/hooks/useChatRealtime.ts
import { useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQueryClient } from '@tanstack/react-query';

export const useChatRealtime = (organizationId?: string) => {
  const queryClient = useQueryClient();

  useEffect(() => {
    if (!organizationId) return;

    const channel = supabase
      .channel(`customer_chat:org_${organizationId}`)
      .on('broadcast', { event: 'ticket_transferred' }, (response) => {
        const payload = response.payload;
        // Atualiza o estado local / cache de queries sem refetch completo
        queryClient.invalidateQueries({ queryKey: ['tickets'] });
      })
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          // Reconcilia dados caso haja perda de conexão
          queryClient.invalidateQueries({ queryKey: ['tickets'] });
        }
      });

    return () => {
      supabase.removeChannel(channel);
    };
  }, [organizationId, queryClient]);
};
```

---

## 6. Supabase Storage e Prevenção de Egress Excessivo

### O Problema do Proxy sem Cache
Fazer download de mídias do Supabase Storage por meio de uma rota de backend (`Worker -> supabaseAdmin.storage.download()`) gera **egress do Supabase** a cada chamada. Quando clientes web tocam áudio ou vídeo, emitem dezenas de `Range Requests`. Se o backend baixar o arquivo inteiro do Supabase a cada requisição de range, o consumo de banda cresce exponencialmente.

### Boas Práticas Implementadas

1. **Definição de `cacheControl` no Upload:**
   ```typescript
   await supabase.storage.from('media').upload(filePath, fileBuffer, {
     contentType: mimeType,
     cacheControl: '31536000', // 1 ano de cache para mídias imutáveis
     upsert: false,
   });
   ```

2. **Uso da Cache API na Borda (Cloudflare Cache):**
   Ao intermediar downloads no worker, o arquivo completo deve ser armazenado na borda (`caches.default`) antes de atender solicitações de fatiamento (`Range`):
   ```typescript
   const cache = caches.default;
   const cacheKey = new Request(cleanUrlWithoutRange, { method: 'GET' });
   let cachedResponse = await cache.match(cacheKey);

   if (!cachedResponse) {
     const { data, error } = await supabaseAdmin.storage.from(bucket).download(path);
     // Salva resposta completa no cache da borda
     cachedResponse = new Response(data, {
       headers: { 'Cache-Control': 'public, max-age=31536000, immutable' },
     });
     c.executionCtx.waitUntil(cache.put(cacheKey, cachedResponse.clone()));
   }
   // Apenas então corta os bytes correspondentes ao cabeçalho Range
   ```

3. **Signed URLs para Arquivos Grandes:**
   Para arquivos pesados (> 25 MB), prefere-se gerar uma URL assinada direta do Supabase (`createSignedUrl`) em vez de carregar os bytes no backend.

---

## 7. RAG (Retrieval-Augmented Generation) com pgvector

O projeto utiliza a extensão `vector` para busca semântica em bases de conhecimento por embeddings.

### 7.1. Esquema SQL com pgvector e HNSW

```sql
-- Ativa a extensão de vetores
create extension if not exists vector;

-- Tabela de chunks indexados
create table if not exists public.knowledge_base_chunks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  knowledge_base_id uuid not null references public.knowledge_bases(id) on delete cascade,
  document_id uuid not null references public.knowledge_base_documents(id) on delete cascade,
  chunk_index integer not null,
  content text not null,
  content_hash text not null,
  embedding_model text not null,
  embedding_dimensions integer not null,
  embedding vector(1536) null, -- Ajuste para as dimensões do seu modelo (ex: 1536, 768)
  metadata jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  deleted_at timestamptz null
);

-- Índice HNSW com distância cosseno para alta velocidade de busca
create index if not exists idx_kb_chunks_embedding_hnsw
  on public.knowledge_base_chunks
  using hnsw (embedding vector_cosine_ops)
  where status = 'embedded' and deleted_at is null and embedding is not null;
```

### 7.2. Função RPC de Busca com Isolamento por Organização

```sql
create or replace function public.match_knowledge_base_chunks(
  p_organization_id uuid,
  p_agent_id uuid,
  p_knowledge_base_ids uuid[],
  p_query_embedding vector(1536),
  p_embedding_model text,
  p_embedding_dimensions integer,
  p_match_count integer default 6,
  p_match_threshold double precision default 0.72
)
returns table (
  chunk_id uuid,
  knowledge_base_id uuid,
  document_id uuid,
  content text,
  score double precision,
  metadata jsonb
)
language sql
stable
as $$
  select
    c.id as chunk_id,
    c.knowledge_base_id,
    c.document_id,
    c.content,
    1 - (c.embedding <=> p_query_embedding) as score,
    c.metadata
  from public.knowledge_base_chunks c
  where c.organization_id = p_organization_id
    and c.knowledge_base_id = any(p_knowledge_base_ids)
    and c.status = 'embedded'
    and c.deleted_at is null
    and c.embedding is not null
    and c.embedding_model = p_embedding_model
    and c.embedding_dimensions = p_embedding_dimensions
    and (1 - (c.embedding <=> p_query_embedding)) >= p_match_threshold
  order by c.embedding <=> p_query_embedding
  limit least(greatest(p_match_count, 1), 20);
$$;
```

### 7.3. Execução da Busca via TypeScript

```typescript
// src/ai/rag/vectorStore.ts
export class SupabaseVectorStore {
  constructor(private readonly supabase: any) {}

  async search(input: {
    organizationId: string;
    agentId: string;
    knowledgeBaseIds: string[];
    queryEmbedding: number[];
    embeddingModel: string;
    embeddingDimensions: number;
    limit: number;
    threshold: number;
  }) {
    const { data, error } = await this.supabase.rpc('match_knowledge_base_chunks', {
      p_organization_id: input.organizationId,
      p_agent_id: input.agentId,
      p_knowledge_base_ids: input.knowledgeBaseIds,
      p_query_embedding: input.queryEmbedding,
      p_embedding_model: input.embeddingModel,
      p_embedding_dimensions: input.embeddingDimensions,
      p_match_count: input.limit,
      p_match_threshold: input.threshold,
    });

    if (error) throw new Error(`Falha na busca vetorial: ${error.message}`);

    return (data || []).map((row: any) => ({
      chunkId: row.chunk_id,
      content: row.content,
      score: Number(row.score),
      metadata: row.metadata,
    }));
  }
}
```

---

## 8. Funções RPC para Operações Críticas e Atômicas

Para operações que exigem incremento atômico de cotas ou inserções transacionais sem condições de corrida (race conditions), criam-se Stored Procedures no Supabase chamadas via `.rpc()`.

### Exemplo: Incremento Seguro de Uso de Quota

```sql
create or replace function public.increment_organization_usage(
  org_id uuid,
  amount integer
)
returns void
language sql
as $$
  update public.organization_quotas
  set current_usage = current_usage + amount,
      updated_at = now()
  where organization_id = org_id;
$$;
```

Chamada via SDK:
```typescript
await supabase.rpc('increment_organization_usage', {
  org_id: organizationId,
  amount: 1,
});
```

---

## 9. Padrão de Repositório (Repository Pattern)

Para manter o domínio e as regras de negócio desacopladas do Supabase, o código utiliza adaptadores de persistência:

```typescript
export interface IContractRepository {
  getById(id: string): Promise<Contract | null>;
  create(input: CreateContractInput): Promise<Contract>;
}

export class SupabaseContractRepository implements IContractRepository {
  constructor(
    private readonly supabase: SupabaseClient,
    private readonly organizationId: string,
  ) {}

  async getById(id: string): Promise<Contract | null> {
    const { data, error } = await this.supabase
      .from('contracts')
      .select('id, title, status, created_at')
      .eq('id', id)
      .eq('organization_id', this.organizationId)
      .maybeSingle();

    if (error) throw new Error(`Erro ao buscar contrato: ${error.message}`);
    if (!data) return null;

    return data;
  }
}
```

---

## 10. Checklist de Configuração para Novos Projetos

### Variáveis de Ambiente Necessárias

| Variável | Onde Usar | Descrição |
|---|---|---|
| `VITE_SUPABASE_URL` | Frontend | URL pública do projeto Supabase |
| `VITE_SUPABASE_ANON_KEY` | Frontend | Chave pública do Supabase com restrições de RLS |
| `SUPABASE_URL` | Backend / Workers | URL do projeto Supabase |
| `SUPABASE_ANON_KEY` | Backend / Workers | Chave anônima utilizada para instanciar clientes de usuário |
| `SUPABASE_SERVICE_ROLE_KEY` | Backend / Workers (Segredo) | Chave com privilégios de superusuário (bypassa RLS) |
| `SUPABASE_JWT_SECRET` | Backend / Workers (Segredo) | Segredo para validação de JWTs HS256 (quando aplicável) |
| `SUPABASE_PROJECT_ID` | Backend / Workers | Identificador do projeto (usado para montar URL de JWKS) |

### Recomendações Críticas para Futuros Projetos
1. **Nunca exponha a `SERVICE_ROLE_KEY`** em builds de frontend ou em repositórios públicos.
2. **Sempre ative RLS** em novas tabelas (`alter table <nome> enable row level security;`).
3. **Evite WebSockets no Backend Serverless:** Utilize a rota REST HTTP Broadcast (`/realtime/v1/api/broadcast`).
4. **Proteja o Storage:** Não configure proxies sem cache na borda para não inflar a cota de egress.
5. **Prefira índices HNSW a IVFFlat** no `pgvector` para performance superior sem necessidade de rebuild frequente.
