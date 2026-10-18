# ARQUITETURA EDGE FULLSTACK: CLOUDFLARE WORKERS (HONO) + SUPABASE + REACT SPA (VERCEL)
> **Stack:** Cloudflare Workers (Hono API + Queues) · Supabase (PostgreSQL + RLS + Realtime) · Vercel (React SPA + Tailwind CSS + Shadcn UI)  
> **Classificação:** Especificação Técnica de Arquitetura & Diretiva para Agentes de IA  
> **Objetivo:** Fornecer à IA um guia determinístico, exaustivo e sem ambiguidades para projetar, estruturar e codificar sistemas fullstack desacoplados seguindo o padrão de produção DVG.

---

## 1. PRINCÍPIOS FUNDAMENTAIS & AXIOMAS ARQUITETURAIS (SYSTEM INVARIANTS)

Toda IA que for gerar ou manter projetos baseados neste modelo DEVE obedecer estritamente aos seguintes 8 axiomas:

### Axioma 1: Separação Radical de Responsabilidades (Fast Dumb Backend / Smart Reactive Frontend)
- **Backend (API Edge):** É exclusivamente uma autoridade de validação, segurança e persistência de dados. Processa I/O ultra-rápido, valida contratos via Zod (`@hono/zod-validator`), gerencia autenticação e devolve dados normalizados em JSON. **Não renderiza HTML nem executa manipulação de layout.**
- **Frontend (SPA):** Detém o controle total de estados de UI, navegação, cache de dados em memória (TanStack Query + Zustand), formatação visual de dados (parsers) e responsividade mobile-first.

### Axioma 2: Padrão Zero-Block Obrigatório no Edge
- **Regra:** NENHUMA requisição HTTP deve esperar tarefas secundárias (envio de e-mails, webhooks de saída, métricas assíncronas, logs de auditoria).
- **Implementação:** Toda tarefa assíncrona que não impacta a resposta imediata DEVE ser envolvida pelo helper `aoFundo(c, promise)` utilizando `c.executionCtx.waitUntil(promise)`, ou enfileirada via Cloudflare Queues (`c.env.QUEUE.send(...)`).
- **Proibido:** Fazer `await resend.emails.send(...)` ou `await fetch(webhookUrl)` no caminho crítico da resposta HTTP.

### Axioma 3: Isolamento de Regras Puras (Pure Domain Rules)
- Toda regra de negócio (cálculos de pontuação, lógica de permissão, regras de agendamento, limites de plano) DEVE residir na pasta `src/rules/` ou `src/domain/` como **funções puras em TypeScript**.
- Essas funções não realizam chamadas de rede nem consultas a banco de dados. Elas recebem dados, processam e retornam o resultado.
- Cada arquivo de regra DEVE ter um arquivo de teste unitário correspondente (`.test.ts`) executável instantaneamente via Vitest.

### Axioma 4: Autenticação Criptográfica em Borda com Resiliência (Dual JWKS / Secret)
- Validação de JWT ocorre **localmente na borda via WebCrypto (`jose`)**, sem roundtrip HTTP ao Supabase Auth na maioria das requisições.
- Suporte a tokens assimétricos modernos (RS256/ES256) via JWKS com cache in-memory e timeout com fallback gracioso para `supabaseAdmin.auth.getUser(token)`.
- **Tratamento granular de erros de JWT:** Identificar e responder distintamente para `TOKEN_EXPIRED`, `TOKEN_INVALID` e `TOKEN_TAMPERED`.

### Axioma 5: Armazenamento Seguro de Tokens (Cookies HttpOnly para Refresh Token)
- **Access Token:** Mantido em memória e/ou `localStorage` (vida curta, ex: 1 hora).
- **Refresh Token:** **NUNCA** armazenado em `localStorage`. Deve trafegar exclusivamente em cookie `httpOnly`, `Secure`, `SameSite=Lax` emitido pelo Worker (`/auth/refresh`), blindando a aplicação contra roubo de credenciais via XSS.

### Axioma 6: Gateway com Deduplicação de Refresh e Eventos Globais de Plataforma
- O frontend não realiza chamadas com `fetch` ou `axios` dispersas sem interceptador. Utiliza um cliente centralizado `gateway.ts`.
- **Deduplicação de refresh:** Quando múltiplas requisições simultâneas tomam 401, elas compartilham a mesma Promise de renovação (`refreshPromise`), evitando race conditions e invalidação indevida de token rotation.
- **Eventos Globais via `window.dispatchEvent`:**
  - `auth:unauthorized`: 401 definitivo (limpa estado e redireciona).
  - `auth:suspended`: 403 por membro suspenso na organização (`MEMBER_SUSPENDED`).
  - `plan:limit`: 402 ou `PLAN_LIMIT` (abre modal de upgrade sem poluir componentes).

### Axioma 7: Segurança em Camadas (Defense in Depth & Inquebrabilidade de CORS)
- **CORS Resiliente até em Falhas:** O handler `app.onError` SEMPRE anexa os headers de CORS explicitamente na resposta 500, impedindo que erros não capturados sejam mascarados no navegador como falhas de política de CORS.
- **Security Headers Automáticos:** `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `X-XSS-Protection: 1; mode=block`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` restritiva e header `Server` oculto.
- **Cache-Control Rigoroso:** APIs REST recebem `Cache-Control: no-store` por padrão.

### Axioma 8: Supabase Realtime com Sincronização Contínua de Auth
- A conexão WebSocket do Supabase Realtime fecha silenciosamente após 1h quando o JWT inicial expira. O frontend DEVE sincronizar o novo token com o socket a cada refresh via `supabase.realtime.setAuth(token)`.
- Disparos de broadcast no frontend devem validar o estado do canal ou utilizar `channel.httpSend()` explícito para evitar avisos de depreciação do SDK.

---

## 2. TOPOLOGIA DO ECOSSISTEMA & FLUXO DE DADOS

```
[ Usuário / Navegador / Mobile ]
        │
        ├── 1. Carrega SPA Estática ─────────► [ Vercel Edge Network ]
        │                                       (React + Vite + Tailwind + Shadcn UI)
        │
        └── 2. Chamadas REST / JSON ─────────► [ Cloudflare Workers (Hono API) ]
                (Cookie HttpOnly anexado)       │
                                                ├── 2a. JWKS Cache Local (jose) ────► [ Validação JWT offline ]
                                                │
                                                ├── 2b. Rate Limiter Nativo ────────► [ CF Rate Limiting por Tier ]
                                                │
                                                ├── 2c. I/O Rápido (PostgREST / RPC) ► [ Supabase DB (PostgreSQL + RLS) ]
                                                │       (com x-actor-id para auditoria)
                                                │
                                                ├── 2d. Background (waitUntil/Queues) [ Cloudflare Queues / Resend ]
                                                │
                                                └── 2e. Supabase Realtime Broadcast ─► [ Realtime REST API ]
```

---

## 3. ESPECIFICAÇÃO DO BACKEND (CLOUDFLARE WORKERS + HONO)

### 3.1 Estrutura Canônica de Diretórios
```
backend/
├── .env.example
├── tsconfig.json
├── wrangler.toml
├── vitest.config.mts
├── package.json
└── src/
    ├── index.ts                # Entrypoint: fetch, scheduled e queue handlers
    ├── app.ts                  # Instância Hono, CORS resiliente, rotas e error handling
    ├── core/                   # Handlers de filas (Queues) e tarefas agendadas (Cron)
    │   ├── scheduledHandler.ts
    │   └── queueHandler.ts
    ├── lib/
    │   ├── aofundo.ts          # Zero-Block pattern (c.executionCtx.waitUntil)
    │   ├── auth.ts             # Extração rápida de usuário (0ms payload parsing)
    │   └── supabase.ts         # getSupabase, getSupabaseAdmin (x-actor-id) e getEffectiveSupabase
    ├── middlewares/
    │   ├── verifyJwt.ts        # Validação criptográfica (JWKS + HS256 + fallback getUser)
    │   ├── securityHeaders.ts  # Injeção de headers de segurança e CSP
    │   ├── rateLimiter.ts      # Cloudflare Rate Limiting por organização/tier com cache
    │   └── auth/types.ts       # Tipos do Hono Context (IEnv, IVariables)
    ├── domain/                 # Regras puras e enums 'as const' (Zero I/O, 100% testáveis)
    │   ├── [entidade].ts
    │   └── [entidade].test.ts
    ├── validation/             # Schemas Zod de entrada
    │   └── [entidade].schema.ts
    ├── services/               # Lógica de integração e orquestração
    │   └── [servico].service.ts
    └── routes/                 # Roteadores modulares Hono
        ├── auth/               # signin, signup, refresh (Set-Cookie httpOnly)
        ├── users/
        ├── organizations/
        └── [modulo].ts
```

### 3.2 Dependências de Produção (`package.json`)
```json
{
  "name": "app-backend",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "wrangler dev --env-file .env.local",
    "deploy": "wrangler deploy --minify",
    "typecheck": "tsc --noEmit",
    "test": "vitest run"
  },
  "dependencies": {
    "@hono/zod-validator": "^0.7.6",
    "@supabase/supabase-js": "^2.49.0",
    "date-fns": "^4.1.0",
    "hono": "^4.11.0",
    "jose": "^6.1.0",
    "resend": "^6.2.0",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "^4.20251011.0",
    "typescript": "^5.7.0",
    "vitest": "^3.0.0",
    "wrangler": "^3.110.0"
  }
}
```

### 3.3 Configuração Canônica do Worker (`wrangler.toml`)
```toml
name = "app-backend"
main = "src/index.ts"
compatibility_date = "2025-09-24"
compatibility_flags = ["nodejs_compat"]

[vars]
FRONTEND_URL = "https://meu-app.vercel.app"
CORS_ORIGINS = "https://dash.meu-app.com,https://admin.meu-app.com"

# === Cloudflare Queues (Filas Assíncronas) ===
# [[queues.producers]]
# queue = "async-tasks-queue"
# binding = "TASKS_QUEUE"
#
# [[queues.consumers]]
# queue = "async-tasks-queue"
# max_batch_size = 20
# max_concurrency = 5
# retry_delay = 30

# === Rate Limiting por Tier da Organização ===
# [[ratelimit]]
# binding = "RATE_LIMITER_TIER_0"
# namespace_id = "1001"
# simple = { limit = 30, period = 60 }
#
# [[ratelimit]]
# binding = "RATE_LIMITER_TIER_1"
# namespace_id = "1002"
# simple = { limit = 120, period = 60 }

# Segredos gerenciados via `wrangler secret put`:
# SUPABASE_URL
# SUPABASE_ANON_KEY
# SUPABASE_SERVICE_ROLE_KEY
# SUPABASE_JWT_SECRET
# RESEND_API_KEY
```

### 3.4 Código Canônico: Inst instanciação do Hono com CORS Resiliente e Security Headers (`src/app.ts`)
```typescript
import { Hono } from "hono";
import { cors } from "hono/cors";
import { securityHeaders } from "./middlewares/securityHeaders";
import { verifyJwt } from "./middlewares/verifyJwt";
import { rateLimiter } from "./middlewares/rateLimiter";

export type Bindings = {
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  SUPABASE_JWT_SECRET?: string;
  SUPABASE_PROJECT_ID?: string;
  FRONTEND_URL: string;
  CORS_ORIGINS?: string;
  RATE_LIMITER_TIER_0?: any;
  RATE_LIMITER_TIER_1?: any;
};

export type Variables = {
  token: string | null;
  user: { id: string; email?: string } | null;
  organization_id?: string;
};

export const app = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// Domínios conhecidos para CORS
const ALLOWED_LOCALHOST = /^http:\/\/(localhost|127\.0\.0\.1):\d+$/;
const ALLOWED_VERCEL_PREVIEWS = /^https:\/\/.*\.vercel\.app$/;

function isOriginAllowed(origin: string | undefined, env: Bindings): boolean {
  if (!origin) return false;
  const configured = [
    env.FRONTEND_URL,
    ...(env.CORS_ORIGINS || "").split(",")
  ].map((u) => u.trim().replace(/\/$/, "")).filter(Boolean);

  const clean = origin.replace(/\/$/, "");
  return configured.includes(clean) || ALLOWED_VERCEL_PREVIEWS.test(clean) || ALLOWED_LOCALHOST.test(clean);
}

// 1. CORS Middleware
app.use("*", async (c, next) => {
  const origin = c.req.header("Origin");
  const path = new URL(c.req.url).pathname;

  // Rotas públicas (webhooks, forms, links) aceitam qualquer origem
  if (/^\/(webhooks|public|l\/)/.test(path)) {
    c.header("Access-Control-Allow-Origin", origin || "*");
    c.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    if (c.req.method === "OPTIONS") return c.text("", 204);
    return next();
  }

  const corsHandler = cors({
    origin: (orig) => (isOriginAllowed(orig, c.env) ? orig : ""),
    allowHeaders: [
      "Authorization",
      "Content-Type",
      "Range",
      "x-advg-client-token",
      "x-organization-id",
    ],
    allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    credentials: true,
    maxAge: 600,
  });

  return corsHandler(c, next);
});

// 2. Headers de Segurança e desativação de cache
app.use("*", securityHeaders);
app.use("*", async (c, next) => {
  await next();
  if (!c.res.headers.has("Cache-Control")) {
    c.res.headers.set("Cache-Control", "no-store");
  }
});

// 3. Autenticação e Rate Limiter condicional
const PUBLIC_PREFIXES = ["/ping", "/auth", "/webhooks", "/public", "/l/"];

app.use("*", async (c, next) => {
  const path = new URL(c.req.url).pathname;
  if (PUBLIC_PREFIXES.some((p) => path === p || path.startsWith(p))) {
    return next();
  }
  return verifyJwt(c, next);
});

app.use("*", rateLimiter);

// 4. Inquebrabilidade de CORS no onError
app.onError((err, c) => {
  console.error("[API_ERROR]", err);
  const reqOrigin = c.req.header("Origin");
  if (reqOrigin && isOriginAllowed(reqOrigin, c.env)) {
    c.header("Access-Control-Allow-Origin", reqOrigin);
    c.header("Access-Control-Allow-Credentials", "true");
  }
  return c.json({ error: err.message || "Erro interno do servidor." }, 500);
});

app.get("/ping", (c) => c.text("pong"));

export default app;
```

### 3.5 Código Canônico: Validação Criptográfica de JWT (`src/middlewares/verifyJwt.ts`)
```typescript
import { MiddlewareHandler } from "hono";
import { jwtVerify, decodeProtectedHeader, createRemoteJWKSet, errors as joseErrors } from "jose";

const jwksCache = new Map<string, any>();

function getOrCreateJWKS(projectId: string) {
  if (!jwksCache.has(projectId)) {
    const jwks = createRemoteJWKSet(
      new URL(`https://${projectId}.supabase.co/auth/v1/.well-known/jwks.json`),
      {
        timeoutDuration: 10000,
        cooldownDuration: 30000,
        cacheMaxAge: 10 * 60 * 1000, // 10 min
      }
    );
    jwksCache.set(projectId, jwks);
  }
  return jwksCache.get(projectId);
}

export const verifyJwt: MiddlewareHandler = async (c, next) => {
  const authorization = c.req.header("Authorization");
  if (!authorization) {
    return c.json({ code: "UNAUTHORIZED", message: "Token de autorização ausente." }, 401);
  }

  const [prefix, token] = authorization.split(" ");
  if (!/^Bearer$/i.test(prefix) || !token) {
    return c.json({ code: "UNAUTHORIZED", message: "Formato de token inválido." }, 401);
  }

  const projectId = c.env.SUPABASE_PROJECT_ID || c.env.SUPABASE_URL.replace("https://", "").split(".")[0];
  const jwtSecret = c.env.SUPABASE_JWT_SECRET;

  try {
    const header = decodeProtectedHeader(token);
    let payload: any;

    if (header.alg === "HS256" && jwtSecret) {
      const secret = new TextEncoder().encode(jwtSecret);
      const res = await jwtVerify(token, secret, {
        issuer: `https://${projectId}.supabase.co/auth/v1`,
      });
      payload = res.payload;
    } else {
      const jwks = getOrCreateJWKS(projectId);
      const res = await jwtVerify(token, jwks, {
        issuer: `https://${projectId}.supabase.co/auth/v1`,
      });
      payload = res.payload;
    }

    c.set("token", token);
    if (payload.sub) {
      c.set("user", { id: payload.sub, email: payload.email });
    }

    return next();
  } catch (err: any) {
    if (err instanceof joseErrors.JWTExpired) {
      return c.json({ code: "TOKEN_EXPIRED", message: "Sessão expirada." }, 401);
    }
    if (err instanceof joseErrors.JWSSignatureVerificationFailed) {
      return c.json({ code: "TOKEN_TAMPERED", message: "Assinatura do token inválida." }, 401);
    }

    // Fallback resiliente se o JWKS do Supabase der timeout
    if (err?.code === "ERR_JWKS_TIMEOUT" || err?.message?.includes("timed out")) {
      console.warn("[JWKS_TIMEOUT] Executando fallback via Supabase Admin API");
      try {
        const { getSupabaseAdmin } = await import("../lib/supabase");
        const supabase = getSupabaseAdmin(c);
        const { data: { user }, error } = await supabase.auth.getUser(token);
        if (!error && user) {
          c.set("token", token);
          c.set("user", { id: user.id, email: user.email });
          return next();
        }
      } catch (fallbackError) {
        console.error("[AUTH_FALLBACK_ERROR]", fallbackError);
      }
    }

    return c.json({ code: "TOKEN_INVALID", message: "Token inválido." }, 401);
  }
};
```

### 3.6 Código Canônico: Instanciação do Supabase no Worker com Auditoria (`src/lib/supabase.ts`)
```typescript
import { createClient, SupabaseClient } from "@supabase/supabase-js";

export const createSupabaseClient = (
  url: string,
  key: string,
  accessToken?: string,
  extraHeaders?: Record<string, string>
): SupabaseClient => {
  const options: any = {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  };

  const headers: Record<string, string> = { ...extraHeaders };
  if (accessToken) headers.Authorization = `Bearer ${accessToken}`;
  if (Object.keys(headers).length > 0) options.global = { headers };

  return createClient(url, key, options);
};

/**
 * Cliente com escopo do usuário logado (passa Bearer token).
 * Garante RLS nativo e auth.uid() no PostgreSQL.
 */
export const getSupabase = (c: any): SupabaseClient => {
  return createSupabaseClient(
    c.env.SUPABASE_URL,
    c.env.SUPABASE_ANON_KEY,
    c.get("token")
  );
};

/**
 * Cliente administrativo com Service Role Key (ignora RLS).
 * Propaga 'x-actor-id' para triggers de auditoria (audit_logs) registrarem o autor.
 */
export const getSupabaseAdmin = (c: any): SupabaseClient => {
  const user = c.get("user");
  return createSupabaseClient(
    c.env.SUPABASE_URL,
    c.env.SUPABASE_SERVICE_ROLE_KEY,
    undefined,
    user?.id ? { "x-actor-id": user.id } : undefined
  );
};

/**
 * Alterna dinamicamente entre admin e usuário se for superadmin / impersonação.
 */
export const getEffectiveSupabase = async (c: any, userId?: string): Promise<SupabaseClient> => {
  const admin = getSupabaseAdmin(c);
  const uid = userId || c.get("user")?.id;
  if (!uid) return getSupabase(c);

  const { data: profile } = await admin
    .from("profiles")
    .select("is_superadmin")
    .eq("id", uid)
    .maybeSingle();

  return profile?.is_superadmin ? admin : getSupabase(c);
};
```

### 3.7 Código Canônico: Entrypoint do Worker com Queues (`src/index.ts`)
```typescript
import { app } from "./app";

export default {
  fetch(request: Request, env: any, ctx: any) {
    return app.fetch(request, env, ctx);
  },

  async scheduled(event: any, env: any, ctx: any) {
    ctx.waitUntil(
      (async () => {
        console.log(`[CRON] Executando rotina agendada: ${event.cron}`);
        // Ex: limpeza de registros expirados, sincronizações periódicas
      })()
    );
  },

  async queue(batch: any, env: any, ctx: any) {
    console.log(`[QUEUE] Processando mensagens da fila: ${batch.queue} (${batch.messages.length} msgs)`);
    for (const message of batch.messages) {
      try {
        // Processar mensagem
        message.ack();
      } catch (err) {
        console.error("[QUEUE_ERROR] Falha ao processar mensagem", err);
        message.retry();
      }
    }
  },
};
```

---

## 4. ESPECIFICAÇÃO DO FRONTEND (REACT + VITE + TAILWIND + SHADCN UI + VERCEL)

### 4.1 Estrutura Canônica de Diretórios
```
frontend/
├── index.html
├── vite.config.ts
├── tsconfig.json
├── vercel.json
├── package.json
└── src/
    ├── main.tsx
    ├── index.css                   # Tailwind v4 (@import "tailwindcss") ou v3 com variáveis Shadcn
    ├── router.tsx                  # Rotas públicas e rotas protegidas (ProtectedRoute)
    ├── services/
    │   └── gateway.ts              # Cliente API centralizado (deduplicação de refresh, eventos globais)
    ├── integrations/
    │   └── supabase/
    │       ├── client.ts           # Supabase JS + syncRealtimeAuth + sendRealtimeBroadcast
    │       └── types.ts            # Tipos gerados do banco (supabase gen types)
    ├── stores/
    │   └── organizationStore.ts    # Zustand para estado global de tenant / preferências
    ├── contexts/
    │   └── AuthContext.tsx         # Provedor de autenticação e sessão
    ├── providers/
    │   └── QueryProvider.tsx       # TanStack QueryClient Provider
    ├── components/
    │   ├── ui/                     # Componentes Shadcn (button, dialog, input, table, sonner)
    │   └── layout/                 # Sidebar, Header, NotificationBell, Modais Globais
    ├── hooks/
    │   ├── use[Entidade].ts        # Hooks combinando useQuery/useMutation com gateway
    │   └── useChatRealtime.ts      # Exemplo de consumo reativo do Realtime
    └── pages/
        ├── auth/                   # Login, Register, VerifyOtp
        └── dashboard/              # Telas autenticadas
```

### 4.2 Código Canônico: Gateway Client de Alta Resiliência (`src/services/gateway.ts`)
```typescript
export const API_URL = import.meta.env.VITE_API_URL?.replace(/\/+$/, '') || 'http://localhost:8787';
export const CLIENT_TOKEN = import.meta.env.VITE_CLIENT_TOKEN || 'client-secret-app';

export interface GatewayError extends Error {
  status?: number;
  code?: string;
  data?: any;
}

interface RequestOptions extends RequestInit {
  token?: string;
  baseUrl?: string;
  _retried?: boolean;
}

let refreshPromise: Promise<string | null> | null = null;

/**
 * Renova o access_token usando o refresh_token mantido em cookie httpOnly.
 * Deduplica chamadas concorrentes: se 10 requisições tomarem 401 juntas,
 * disparam apenas 1 requisição para /auth/refresh.
 */
export async function refreshAccessToken(): Promise<string | null> {
  if (refreshPromise) return refreshPromise;

  refreshPromise = (async () => {
    try {
      const res = await fetch(`${API_URL}/auth/refresh`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-advg-client-token': CLIENT_TOKEN },
        credentials: 'include', // Envia o cookie httpOnly
      });
      if (!res.ok) return null;

      const data = await res.json();
      const token = data.session?.access_token;
      if (!token) return null;

      localStorage.setItem('auth_token', token);
      window.dispatchEvent(new CustomEvent('auth:token-refreshed', { detail: data.session }));
      return token;
    } catch {
      return null;
    }
  })();

  try {
    return await refreshPromise;
  } finally {
    refreshPromise = null;
  }
}

export const gateway = {
  async request<T>(endpoint: string, options: RequestOptions = {}): Promise<T> {
    const url = `${options.baseUrl || API_URL}${endpoint}`;
    const headers = new Headers(options.headers);

    if (!(options.body instanceof FormData)) {
      headers.set('Content-Type', 'application/json');
    }
    headers.set('x-advg-client-token', CLIENT_TOKEN);

    const token = options.token || localStorage.getItem('auth_token');
    if (token) {
      headers.set('Authorization', `Bearer ${token}`);
    }

    const response = await fetch(url, {
      ...options,
      headers,
      credentials: 'include',
    });

    const data = await response.json().catch(() => ({}));

    if (!response.ok) {
      // 1. Tratamento transparente de 401 com retry único pós-refresh
      if (response.status === 401 && !options._retried && !options.token && !endpoint.startsWith('/auth/')) {
        const newToken = await refreshAccessToken();
        if (newToken) {
          return gateway.request<T>(endpoint, { ...options, token: newToken, _retried: true });
        }
      }

      // 2. 401 definitivo: desloga e avisa a aplicação
      if (response.status === 401) {
        localStorage.removeItem('auth_token');
        window.dispatchEvent(new Event('auth:unauthorized'));
      }

      // 3. 403 Membro Suspenso
      if (response.status === 403 && data.code === 'MEMBER_SUSPENDED') {
        window.dispatchEvent(
          new CustomEvent('auth:suspended', { detail: { message: data.message || 'Acesso suspenso.' } })
        );
      }

      // 4. 402 ou PLAN_LIMIT: abre modal de upgrade global
      if (response.status === 402 || data.code === 'PLAN_LIMIT') {
        window.dispatchEvent(
          new CustomEvent('plan:limit', { detail: { message: data.message, ...data } })
        );
      }

      const error = new Error(data.message || data.error || 'Falha na requisição.') as GatewayError;
      error.status = response.status;
      error.code = data.code;
      error.data = data;
      throw error;
    }

    return data as T;
  },

  get<T>(endpoint: string, options?: RequestOptions) {
    return gateway.request<T>(endpoint, { ...options, method: 'GET' });
  },

  post<T>(endpoint: string, body: any, options?: RequestOptions) {
    return gateway.request<T>(endpoint, {
      ...options,
      method: 'POST',
      body: body instanceof FormData ? body : JSON.stringify(body),
    });
  },

  put<T>(endpoint: string, body: any, options?: RequestOptions) {
    return gateway.request<T>(endpoint, {
      ...options,
      method: 'PUT',
      body: body instanceof FormData ? body : JSON.stringify(body),
    });
  },

  delete<T>(endpoint: string, options?: RequestOptions) {
    return gateway.request<T>(endpoint, { ...options, method: 'DELETE' });
  },
};
```

### 4.3 Código Canônico: Supabase Client & Sincronização de WebSocket Realtime (`src/integrations/supabase/client.ts`)
```typescript
import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || "";
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY || "";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Garante que o RealtimeClient sempre use o JWT mais recente do Gateway
(supabase.realtime as any).accessToken = async () => {
  return (typeof window !== "undefined" ? localStorage.getItem("auth_token") : null) || SUPABASE_ANON_KEY;
};

let lastSyncedToken: string | null = null;

/**
 * Sincroniza o JWT com a conexão WebSocket do Supabase.
 * Previne que canais caiam após 1 hora por "Token Expired".
 */
export function syncRealtimeAuth(token: string | null) {
  if (!token || token === lastSyncedToken) return;
  try {
    lastSyncedToken = token;
    supabase.realtime.setAuth(token);
    console.log("[Supabase Realtime] Token sincronizado com WebSocket.");
  } catch (err) {
    console.error("[Supabase Realtime] Erro ao sincronizar token com WebSocket:", err);
  }
}

/**
 * Broadcast seguro que evita deprecation warning usando httpSend() se o canal não estiver em push ativo.
 */
export async function sendRealtimeBroadcast(
  channelName: string,
  event: string,
  payload: Record<string, any>
): Promise<void> {
  const channel = supabase.channel(channelName);
  const canPush = Boolean((channel as any).channelAdapter?.canPush?.() || (channel as any).canPush?.());

  if (canPush) {
    await channel.send({ type: "broadcast", event, payload });
  } else if (typeof (channel as any).httpSend === "function") {
    await (channel as any).httpSend(event, payload);
  } else {
    await channel.send({ type: "broadcast", event, payload });
  }
}
```

### 4.4 Configuração de Deploy Vercel SPA (`vercel.json`)
```json
{
  "rewrites": [
    { "source": "/(.*)", "destination": "/index.html" }
  ],
  "headers": [
    {
      "source": "/assets/(.*)",
      "headers": [
        { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
      ]
    },
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Frame-Options", "value": "DENY" },
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" }
      ]
    }
  ]
}
```

---

## 5. ALGORITMO DE CONSTRUÇÃO PARA A IA (STEP-BY-STEP RUNBOOK)

Quando uma IA for instruída a criar ou expandir um sistema neste ecossistema, DEVE executar as etapas nesta ordem exata:

```
[ ETAPA 1: BANCO & POLÍTICAS RLS (SUPABASE) ]
  1.1 Modelar schema relacional com migrations SQL no Supabase.
  1.2 Sempre ativar RLS em tabelas expostas: alter table [tabela] enable row level security;
  1.3 Definir políticas multi-tenant baseadas em organization_id ou memberships (auth.uid()).
  1.4 Para tabelas de auditoria/logs, não criar policy de escrita pública: apenas service_role insere.

[ ETAPA 2: BACKEND EDGE (CLOUDFLARE WORKERS + HONO) ]
  2.1 Inicializar Hono com TypeScript estrito ('strict: true').
  2.2 Configurar 'securityHeaders' e CORS dinâmico com onError resiliente (anexando CORS em erro 500).
  2.3 Configurar 'verifyJwt' com suporte dual JWKS + HS256 e fallback para timeout.
  2.4 Criar 'lib/supabase.ts' com getSupabase, getSupabaseAdmin (injetando 'x-actor-id') e getEffectiveSupabase.
  2.5 Isolar regras de negócio puras em 'src/rules/' ou 'src/domain/' com testes Vitest correspondentes.
  2.6 Envolver tarefas secundárias em 'aoFundo' (c.executionCtx.waitUntil) ou Cloudflare Queues.

[ ETAPA 3: FRONTEND SPA (REACT + VITE + TAILWIND + VERCEL) ]
  3.1 Configurar Vite + React + TypeScript com Shadcn UI / Radix primitives.
  3.2 Implementar 'services/gateway.ts' com deduplicação de refresh token e disparo de eventos globais.
  3.3 Configurar 'integrations/supabase/client.ts' com syncRealtimeAuth no WebSocket.
  3.4 Criar 'vercel.json' com reescritas completas e headers de segurança.
  3.5 Configurar TanStack QueryClient Provider com staleTime de 2 minutos.

[ ETAPA 4: VERIFICAÇÃO & QA ]
  4.1 Executar 'npm run typecheck' em ambos os projetos (zero erros de tipagem).
  4.2 Rodar 'vitest run' nas regras de negócio e rotas.
  4.3 Testar rota de erro 500 para garantir que o cabeçalho de CORS é devolvido.
  4.4 Validar renovação de token simulando 401 e checando se o cookie httpOnly é consumido.
```

---

## 6. DIRETRIZES DE ESTILO & RESTRIÇÕES NEGATIVAS (NEGATIVE CONSTRAINTS)

- ❌ **NUNCA** guarde o `refresh_token` no `localStorage`. Utilize cookies `httpOnly`, `Secure` e `SameSite=Lax`.
- ❌ **NUNCA** retorne erro 500 em `app.onError` sem cabeçalhos de CORS, pois o navegador mascarará a falha real como erro de rede/CORS.
- ❌ **NUNCA** faça chamadas `fetch` ou `axios` avulsas no frontend ignorando a camada do `gateway.ts`.
- ❌ **NUNCA** execute mutações de banco de dados diretamente pelo client público do Supabase no frontend caso envolvam cotas, permissões ou auditoria: passe pelo Worker.
- ❌ **NUNCA** importe módulos nativos legados do Node.js (ex: `fs`, `net`, `child_process`) no Worker; use APIs Web Standard (`fetch`, `Request`, `Response`, `WebCrypto`).
- ❌ **NUNCA** suba chaves de produção (`SUPABASE_SERVICE_ROLE_KEY`, `RESEND_API_KEY`) para o repositório Git ou em `wrangler.toml` em claro.
- ❌ **NUNCA** deixe o WebSocket do Supabase Realtime sem sincronizar o token JWT após o refresh, ou a conexão fechará após 60 minutos.
