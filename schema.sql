-- ContaPlena: esquema, segurança (RLS) e cálculos contábeis no banco.
-- Rode inteiro no SQL Editor do Supabase.

create table offices(
  id uuid primary key default gen_random_uuid(),
  name text not null, active boolean not null default true,
  created_at timestamptz not null default now());

create table profiles(
  id uuid primary key references auth.users on delete cascade,
  office_id uuid not null references offices on delete cascade,
  name text, role text not null default 'contador' check (role in ('admin','contador','assistente')));

create table clients(
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices on delete cascade,
  cnpj text not null check (cnpj ~ '^\d{14}$'),
  name text not null, trade_name text, kind text, regime text, email text, address text,
  created_at timestamptz not null default now(),
  unique(office_id,cnpj), unique(id,office_id));

create table accounts(
  client_id uuid not null, office_id uuid not null,
  code text not null check (code ~ '^[1-5](\.\d+)+$'), name text not null,
  primary key(client_id,code),
  foreign key(client_id,office_id) references clients(id,office_id) on delete cascade);

create table entries(
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null, office_id uuid not null,
  date date not null, memo text, debit text not null, credit text not null,
  amount numeric(14,2) not null check (amount>0),
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  foreign key(client_id,office_id) references clients(id,office_id) on delete cascade);
create index on entries(client_id,date);

-- Plano de contas padrão criado com cada cliente
create function clients_defaults() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into accounts(client_id,office_id,code,name) select new.id,new.office_id,c,n from (values
   ('1.1.01','Caixa'),('1.1.02','Bancos c/c'),('1.1.03','Clientes a receber'),('1.2.01','Imobilizado'),
   ('2.1.01','Fornecedores'),('2.1.02','Impostos a recolher'),('2.1.03','Salários a pagar'),
   ('3.1.01','Capital social'),('4.1.01','Receita de serviços'),('4.1.02','Receita de vendas'),
   ('5.1.01','Custo das mercadorias'),('5.2.01','Despesas administrativas'),('5.2.02','Aluguel'),
   ('5.2.03','Despesas com pessoal'),('5.2.04','Impostos sobre receita')) v(c,n);
  return new; end $$;
create trigger t_clients_defaults after insert on clients for each row execute function clients_defaults();

-- Validação dos lançamentos
create function entries_guard() returns trigger language plpgsql security definer set search_path=public as $$
begin
  select office_id into new.office_id from clients where id=new.client_id;
  if new.office_id is null then raise exception 'Cliente inexistente'; end if;
  if new.debit=new.credit then raise exception 'Débito e crédito na mesma conta'; end if;
  if (select count(*) from accounts where client_id=new.client_id and code in (new.debit,new.credit))<2 then
    raise exception 'Conta inexistente no plano deste cliente'; end if;
  return new; end $$;
create trigger t_entries_guard before insert or update on entries for each row execute function entries_guard();

-- Segurança
create function my_office() returns uuid language sql stable security definer set search_path=public as $$
  select p.office_id from profiles p join offices o on o.id=p.office_id where p.id=auth.uid() and o.active $$;
create function my_role() returns text language sql stable security definer set search_path=public as $$
  select role from profiles where id=auth.uid() $$;
create function is_platform_admin() returns boolean language sql stable as $$
  select coalesce(auth.jwt()->'app_metadata'->>'role','')='platform_admin' $$;

alter table offices enable row level security;  alter table profiles enable row level security;
alter table clients enable row level security;  alter table accounts enable row level security;
alter table entries enable row level security;

create policy offices_read  on offices  for select using (id=my_office() or is_platform_admin());
create policy offices_admin on offices  for all using (is_platform_admin()) with check (is_platform_admin());
create policy profiles_read on profiles for select using (office_id=my_office() or is_platform_admin());
create policy clients_rw  on clients  for all using (office_id=my_office()) with check (office_id=my_office());
create policy accounts_rw on accounts for all using (office_id=my_office()) with check (office_id=my_office());
create policy entries_rw  on entries  for all using (office_id=my_office()) with check (office_id=my_office());
-- Obs.: o administrador da plataforma NÃO lê clientes nem lançamentos. Só gerencia escritórios.

-- Cálculos (security invoker: o RLS vale também aqui)
create function balancete(p_client uuid, p_from date default '0001-01-01', p_to date default '9999-12-31')
returns table(code text,name text,debits numeric,credits numeric,balance numeric)
language sql stable as $$
  select a.code,a.name,coalesce(d.v,0),coalesce(c.v,0),coalesce(d.v,0)-coalesce(c.v,0)
  from accounts a
  left join (select debit k,sum(amount) v from entries where client_id=p_client and date between p_from and p_to group by 1) d on d.k=a.code
  left join (select credit k,sum(amount) v from entries where client_id=p_client and date between p_from and p_to group by 1) c on c.k=a.code
  where a.client_id=p_client order by a.code $$;

create function dre(p_client uuid, p_from date, p_to date)
returns table(grp text,code text,name text,amount numeric) language sql stable as $$
  with b as (select * from balancete(p_client,p_from,p_to))
  select case when left(code,1)='4' then 'receita' else 'despesa' end, code, name,
         case when left(code,1)='4' then -balance else balance end
  from b where left(code,1) in ('4','5') and (debits<>0 or credits<>0)
  union all
  select 'resultado','','Resultado do período', coalesce(-sum(balance),0) from b where left(code,1) in ('4','5') $$;

create function balanco(p_client uuid, p_to date default current_date)
returns table(grp text,code text,name text,amount numeric) language sql stable as $$
  with b as (select * from balancete(p_client,'0001-01-01',p_to))
  select case left(code,1) when '1' then 'ativo' when '2' then 'passivo' else 'pl' end, code, name,
         case when left(code,1)='1' then balance else -balance end
  from b where left(code,1) in ('1','2','3') and (debits<>0 or credits<>0)
  union all
  select 'pl','','Resultado acumulado', coalesce(-sum(balance),0) from b where left(code,1) in ('4','5') $$;

create function razonete(p_client uuid, p_code text, p_from date default '0001-01-01', p_to date default '9999-12-31')
returns table(date date,memo text,side text,amount numeric) language sql stable as $$
  select date,memo,'D',amount from entries where client_id=p_client and debit=p_code and date between p_from and p_to
  union all
  select date,memo,'C',amount from entries where client_id=p_client and credit=p_code and date between p_from and p_to
  order by 1 $$;

create function caixa(p_client uuid, p_from date, p_to date)
returns table(date date,memo text,entrada numeric,saida numeric,saldo numeric) language sql stable as $$
  select * from (
    select e.date,e.memo,
      case when e.debit in ('1.1.01','1.1.02') then e.amount else 0 end,
      case when e.credit in ('1.1.01','1.1.02') then e.amount else 0 end,
      sum((case when e.debit in ('1.1.01','1.1.02') then e.amount else 0 end)
         -(case when e.credit in ('1.1.01','1.1.02') then e.amount else 0 end)) over (order by e.date,e.id)
    from entries e where e.client_id=p_client and e.date<=p_to
      and (e.debit in ('1.1.01','1.1.02') or e.credit in ('1.1.01','1.1.02'))) t(date,memo,entrada,saida,saldo)
  where date>=p_from order by date $$;

create function auditoria(p_client uuid) returns table(nivel text,mensagem text) language sql stable as $$
  with b as (select * from balancete(p_client)),
  r as (select coalesce(-sum(balance) filter (where left(code,1)='4'),0) rec,
               coalesce(sum(balance) filter (where left(code,1)='5'),0) des from b)
  select 'erro','Caixa com saldo negativo' from b where code='1.1.01' and balance<0
  union all select 'erro','Saldo bancário negativo' from b where code='1.1.02' and balance<0
  union all select 'aviso','Despesas maiores que receitas' from r where des>rec $$;

-- Documentos (crie o bucket privado "documents" no painel)
create policy docs_rw on storage.objects for all
  using (bucket_id='documents' and (storage.foldername(name))[1]=my_office()::text)
  with check (bucket_id='documents' and (storage.foldername(name))[1]=my_office()::text);

-- Seu usuário administrador (crie o usuário no Auth e depois rode, com seu e-mail):
-- update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data,'{}'::jsonb)||'{"role":"platform_admin"}' where email='SEU@EMAIL';
