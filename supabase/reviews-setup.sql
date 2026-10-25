-- Run this once in the Supabase SQL Editor.
-- Create a Supabase Auth user for the site owner first, then insert that user's UUID
-- into public.review_admins using the statement at the end of this file.

create table if not exists public.review_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

alter table public.reviews enable row level security;
alter table public.review_admins enable row level security;

grant select on public.reviews to anon, authenticated;
grant insert on public.reviews to anon, authenticated;
grant delete on public.reviews to authenticated;
grant select on public.review_admins to authenticated;

do $$
declare
  reviews_id_sequence text := pg_get_serial_sequence('public.reviews', 'id');
begin
  if reviews_id_sequence is not null then
    execute format('grant usage, select on sequence %s to anon, authenticated', reviews_id_sequence);
  end if;
end;
$$;

drop policy if exists "reviews_public_read" on public.reviews;
create policy "reviews_public_read"
on public.reviews for select to anon, authenticated
using (true);

drop policy if exists "reviews_public_insert" on public.reviews;
create policy "reviews_public_insert"
on public.reviews for insert to anon, authenticated
with check (
  char_length(btrim(name)) between 1 and 80
  and char_length(btrim(comment)) between 1 and 1200
  and rating between 1 and 5
);

drop policy if exists "review_admins_read_self" on public.review_admins;
create policy "review_admins_read_self"
on public.review_admins for select to authenticated
using (user_id = (select auth.uid()));

-- Remove any pre-existing broad DELETE or ALL policy before adding the admin-only policy.
do $$
declare
  existing_policy record;
begin
  for existing_policy in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'reviews'
      and cmd in ('DELETE', 'ALL')
  loop
    execute format('drop policy if exists %I on public.reviews', existing_policy.policyname);
  end loop;
end;
$$;

revoke delete on public.reviews from anon, authenticated;
grant delete on public.reviews to authenticated;

drop policy if exists "reviews_admin_delete" on public.reviews;
create policy "reviews_admin_delete"
on public.reviews for delete to authenticated
using (
  exists (
    select 1 from public.review_admins admins
    where admins.user_id = (select auth.uid())
  )
);

-- Seed the existing site reviews, without duplicating a matching entry.
insert into public.reviews (name, comment, rating, created_at)
select seed.name, seed.comment, seed.rating, now()
from (values
  ('ريم س.', 'شغل تيما خيالي! الرموش خفيفة جداً عالعين وما حسيت بأي ثقل، واستمروا معي شهر كامل متل أول يوم.', 5),
  ('مايا ك.', 'أول مرة بجرب اللفتنغ وكنت خايفة، بس النتيجة طلعت فوق الوصف.. طبيعية ومرتبة بشكل مو طبيعي.', 5),
  ('شهد ع.', 'النظافة والتعقيم والتعامل اللطيف لحالن بيستاهلوا 10 نجوم، غير دقة سحبة الـ Cat Eye اللي بتجنن.', 5)
) as seed(name, comment, rating)
where not exists (
  select 1 from public.reviews existing
  where existing.name = seed.name and existing.comment = seed.comment
);

-- After creating the Auth user, add its UUID here from Supabase > Authentication > Users:
-- insert into public.review_admins (user_id) values ('REPLACE_WITH_AUTH_USER_UUID');