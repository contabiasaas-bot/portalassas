// Edge Function "provision": cria escritório (admin da plataforma), membros (admin do escritório) e redefine senha.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
const out = (b: unknown, s = 200) => new Response(JSON.stringify(b), {status: s, headers: {...cors, 'Content-Type': 'application/json'}})
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', {headers: cors})
  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
  const token = (req.headers.get('Authorization') || '').replace('Bearer ', '')
  const {data: {user}} = await sb.auth.getUser(token)
  if (!user) return out({error: 'Não autenticado'}, 401)
  const b = await req.json().catch(() => ({}))
  const isPlat = user.app_metadata?.role === 'platform_admin'
  const okPw = (p: string) => typeof p === 'string' && p.length >= 8
  const okEm = (e: string) => typeof e === 'string' && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e)

  if (b.action === 'office') {
    if (!isPlat) return out({error: 'Sem permissão'}, 403)
    if (!b.name || !okEm(b.email) || !okPw(b.password)) return out({error: 'Dados inválidos (senha mín. 8)'}, 400)
    const {data: o, error: e1} = await sb.from('offices').insert({name: b.name}).select().single()
    if (e1) return out({error: e1.message}, 400)
    const {data: u, error: e2} = await sb.auth.admin.createUser({email: b.email, password: b.password, email_confirm: true})
    if (e2) { await sb.from('offices').delete().eq('id', o.id); return out({error: e2.message}, 400) }
    await sb.from('profiles').insert({id: u.user.id, office_id: o.id, name: 'Titular', role: 'admin'})
    return out({ok: true})
  }
  if (b.action === 'member') {
    const {data: me} = await sb.from('profiles').select('office_id,role').eq('id', user.id).single()
    if (!me || me.role !== 'admin') return out({error: 'Sem permissão'}, 403)
    if (!okEm(b.email) || !okPw(b.password) || !['contador', 'assistente', 'admin'].includes(b.role)) return out({error: 'Dados inválidos'}, 400)
    const {data: u, error} = await sb.auth.admin.createUser({email: b.email, password: b.password, email_confirm: true})
    if (error) return out({error: error.message}, 400)
    await sb.from('profiles').insert({id: u.user.id, office_id: me.office_id, name: b.name || b.email, role: b.role})
    return out({ok: true})
  }
  if (b.action === 'password') {
    if (!isPlat || !b.user_id || !okPw(b.password)) return out({error: 'Sem permissão ou dados inválidos'}, 400)
    const {error} = await sb.auth.admin.updateUserById(b.user_id, {password: b.password})
    return error ? out({error: error.message}, 400) : out({ok: true})
  }
  return out({error: 'Ação desconhecida'}, 400)
})
