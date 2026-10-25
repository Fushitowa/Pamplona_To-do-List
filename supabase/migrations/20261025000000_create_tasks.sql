create table if not exists public.lexterbeat_tasks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 160),
  notes text not null default '',
  done boolean not null default false,
  status text not null default 'todo' check (status in ('todo', 'progress', 'revision', 'done')),
  priority text not null default 'Medium' check (priority in ('Low', 'Medium', 'High')),
  project text not null default 'Nova UI Revamp',
  due_at timestamptz,
  reminded boolean not null default false,
  color text check (color is null or color in ('yellow', 'mint', 'rose', 'peach', 'sky', 'lilac')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint lexterbeat_tasks_done_matches_status check (done = (status = 'done'))
);

create index if not exists lexterbeat_tasks_owner_created_at_idx
  on public.lexterbeat_tasks (owner_id, created_at desc);

alter table public.lexterbeat_tasks enable row level security;

drop policy if exists "Users can access their own tasks" on public.lexterbeat_tasks;
create policy "Users can access their own tasks"
  on public.lexterbeat_tasks
  for all
  to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

grant select, insert, update, delete on public.lexterbeat_tasks to authenticated;

create or replace function public.set_lexterbeat_tasks_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists lexterbeat_tasks_set_updated_at on public.lexterbeat_tasks;
create trigger lexterbeat_tasks_set_updated_at
  before update on public.lexterbeat_tasks
  for each row execute function public.set_lexterbeat_tasks_updated_at();
