# ContaPlena com Supabase

## 1. Banco e segurança
1. Crie um projeto em supabase.com.
2. SQL Editor: cole e rode `supabase/schema.sql` inteiro.
3. Storage: crie o bucket **privado** `documents`.
4. Authentication > Users: crie o SEU usuário (e-mail e senha forte). Depois rode, no SQL Editor, o `update auth.users ...` que está no final do schema, com o seu e-mail.
5. Authentication > Providers/Settings: senha mínima 8, confirmação de e-mail ligada, limite de tentativas ativo.
   Em URL Configuration, coloque o endereço do seu site em Site URL e Redirect URLs (necessário para "esqueci a senha").

## 2. Edge Function
Com a CLI do Supabase: `supabase functions deploy provision`.
A chave `service_role` é injetada automaticamente. Nunca a coloque no front-end.

## 3. Site
Em `web/index.html`, troque `SUPABASE_URL` e `SUPABASE_ANON_KEY` (Project Settings > API; use a chave **anon**).
Publique a pasta `web` na Vercel, Netlify ou Cloudflare Pages.

## 4. Conferência do contador (antes de vender)
- Lance 5 a 10 movimentos reais de um cliente e compare DRE, balancete e balanço com a contabilidade já fechada.
- Confira: balancete com débitos = créditos; balanço com Ativo = Passivo + PL.
- Valide o plano de contas padrão e ajuste conforme a necessidade de cada cliente.
- Teste com dois escritórios: o escritório A não pode ver nenhum dado do B.
- Teste suspender um escritório (Ativo = falso): ele perde o acesso na hora.
