-- Kniv: synchroniseren en delen. Lokaal-eerst: de app is de bron, dit is de brug tussen apparaten en vrienden.
-- Conflicten: laatste wijziging wint (kolom gewijzigd). Verwijderen = zacht (verwijderd = true), zodat andere apparaten het merken.

create extension if not exists pgcrypto;

create table if not exists profielen (
    id uuid primary key references auth.users on delete cascade,
    naam text not null default '',
    avatar text,
    gemaakt timestamptz not null default now()
);

create table if not exists groepen (
    id uuid primary key default gen_random_uuid(),
    eigenaar uuid not null references auth.users on delete cascade,
    soort text not null,                    -- lijst, countdown, pot, stemming
    titel text not null default '',
    deel_token text unique default encode(gen_random_bytes(12), 'hex'),
    verloopt timestamptz default now() + interval '30 days',
    gemaakt timestamptz not null default now()
);

create table if not exists leden (
    groep uuid references groepen on delete cascade,
    gebruiker uuid references auth.users on delete cascade,
    sinds timestamptz not null default now(),
    primary key (groep, gebruiker)
);

create table if not exists records (
    id uuid primary key,
    eigenaar uuid not null references auth.users on delete cascade,
    groep uuid references groepen on delete cascade,
    soort text not null,                    -- notitie, item, timer, pot, uitgave, stem
    data jsonb not null default '{}',
    gewijzigd timestamptz not null default now(),
    gewijzigd_door uuid references auth.users on delete set null,
    verwijderd boolean not null default false
);
create index if not exists records_eigenaar_gewijzigd on records (eigenaar, gewijzigd);
create index if not exists records_groep_gewijzigd on records (groep, gewijzigd);

create table if not exists vrienden (
    gebruiker uuid references auth.users on delete cascade,
    vriend uuid references auth.users on delete cascade,
    primary key (gebruiker, vriend)
);

create table if not exists ai_gebruik (
    gebruiker uuid references auth.users on delete cascade,
    dag date not null default current_date,
    aantal int not null default 0,
    primary key (gebruiker, dag)
);

-- Lid van een groep? (security definer, zodat de policies niet in een lus raken)
create or replace function is_lid(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (select 1 from leden where groep = g and gebruiker = auth.uid())
        or exists (select 1 from groepen where id = g and eigenaar = auth.uid())
$$;

alter table profielen enable row level security;
alter table groepen enable row level security;
alter table leden enable row level security;
alter table records enable row level security;
alter table vrienden enable row level security;
alter table ai_gebruik enable row level security;

drop policy if exists "profielen lezen" on profielen;
create policy "profielen lezen" on profielen for select to authenticated using (true);
drop policy if exists "eigen profiel" on profielen;
create policy "eigen profiel" on profielen for all to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "groepen zien" on groepen;
create policy "groepen zien" on groepen for select to authenticated using (is_lid(id));
drop policy if exists "groep maken" on groepen;
create policy "groep maken" on groepen for insert to authenticated with check (eigenaar = auth.uid());
drop policy if exists "groep beheren" on groepen;
create policy "groep beheren" on groepen for update to authenticated using (eigenaar = auth.uid());
drop policy if exists "groep weg" on groepen;
create policy "groep weg" on groepen for delete to authenticated using (eigenaar = auth.uid());

drop policy if exists "leden zien" on leden;
create policy "leden zien" on leden for select to authenticated using (is_lid(groep));
drop policy if exists "leden beheren" on leden;
create policy "leden beheren" on leden for all to authenticated
    using (exists (select 1 from groepen where id = groep and eigenaar = auth.uid()) or gebruiker = auth.uid())
    with check (exists (select 1 from groepen where id = groep and eigenaar = auth.uid()));

drop policy if exists "records lezen" on records;
create policy "records lezen" on records for select to authenticated
    using (eigenaar = auth.uid() or (groep is not null and is_lid(groep)));
drop policy if exists "records schrijven" on records;
create policy "records schrijven" on records for insert to authenticated
    with check ((eigenaar = auth.uid() and groep is null) or (groep is not null and is_lid(groep)));
drop policy if exists "records wijzigen" on records;
create policy "records wijzigen" on records for update to authenticated
    using (eigenaar = auth.uid() or (groep is not null and is_lid(groep)));

drop policy if exists "eigen vrienden" on vrienden;
create policy "eigen vrienden" on vrienden for all to authenticated using (gebruiker = auth.uid()) with check (gebruiker = auth.uid());

drop policy if exists "eigen ai" on ai_gebruik;
create policy "eigen ai" on ai_gebruik for select to authenticated using (gebruiker = auth.uid());

-- Nieuwe gebruiker → profiel met naam en foto van Google.
create or replace function nieuw_profiel() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    insert into profielen (id, naam, avatar)
    values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)), new.raw_user_meta_data->>'avatar_url')
    on conflict (id) do nothing;
    return new;
end $$;
drop trigger if exists bij_nieuwe_gebruiker on auth.users;
create trigger bij_nieuwe_gebruiker after insert on auth.users for each row execute function nieuw_profiel();

-- Uitnodigingslink: word lid van een groep met het deeltoken (Google-login vereist).
create or replace function word_lid(token text) returns uuid
language plpgsql security definer set search_path = public as $$
declare g uuid;
begin
    select id into g from groepen where deel_token = token and (verloopt is null or verloopt > now());
    if g is null then raise exception 'Link verlopen of onbekend'; end if;
    insert into leden (groep, gebruiker) values (g, auth.uid()) on conflict do nothing;
    return g;
end $$;

-- Deelpagina (alleen kijken, geen account): groep + records zolang de link geldig is.
create or replace function deelpagina(token text) returns jsonb
language sql stable security definer set search_path = public as $$
    select jsonb_build_object(
        'titel', g.titel, 'soort', g.soort, 'verloopt', g.verloopt,
        'eigenaar', (select naam from profielen where id = g.eigenaar),
        'records', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'soort', r.soort, 'data', r.data, 'door', p.naam, 'avatar', p.avatar) order by r.gewijzigd)
                             from records r left join profielen p on p.id = coalesce(r.gewijzigd_door, r.eigenaar)
                             where r.groep = g.id and not r.verwijderd), '[]'::jsonb),
        -- naam + foto van iedereen die een item toevoegde, voor het profielbolletje per item
        'mensen', coalesce((select jsonb_object_agg(p.id, jsonb_build_object('naam', p.naam, 'avatar', p.avatar))
                            from profielen p
                            where p.id in (select (i->>'door')::uuid from records r, jsonb_array_elements(coalesce(r.data->'items', '[]'::jsonb)) i
                                           where r.groep = g.id and not r.verwijderd and i->>'door' is not null)), '{}'::jsonb))
    from groepen g where g.deel_token = token and (g.verloopt is null or g.verloopt > now())
$$;
grant execute on function deelpagina(text) to anon, authenticated;
grant execute on function word_lid(text) to authenticated;

-- Account verwijderen vanuit de app. Gedeelde groepen gaan over op het langst aanwezige lid.
create or replace function verwijder_mij() returns void
language plpgsql security definer set search_path = public as $$
declare g record; opvolger uuid;
begin
    for g in select id from groepen where eigenaar = auth.uid() loop
        select gebruiker into opvolger from leden where groep = g.id and gebruiker <> auth.uid() order by sinds limit 1;
        if opvolger is null then
            delete from groepen where id = g.id;
        else
            update groepen set eigenaar = opvolger where id = g.id;
            update records set eigenaar = opvolger where groep = g.id and eigenaar = auth.uid();
        end if;
    end loop;
    delete from auth.users where id = auth.uid();
end $$;
grant execute on function verwijder_mij() to authenticated;

-- Live: wijzigingen in records meteen naar de apparaten (Realtime).
do $$ begin
    alter publication supabase_realtime add table records;
exception when duplicate_object then null; end $$;

-- Beheerpaneel (alleen via de service-sleutel in het Windows-programma van Josh).
create or replace view beheer_cijfers as
    select (select count(*) from auth.users) as gebruikers,
           (select count(distinct eigenaar) from records where gewijzigd > now() - interval '1 day') as actief_vandaag,
           (select soort from records group by soort order by count(*) desc limit 1) as populairste_soort;
revoke all on beheer_cijfers from anon, authenticated;
