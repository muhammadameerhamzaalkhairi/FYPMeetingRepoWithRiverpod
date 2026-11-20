-- Narrow the existing INSERT policy for manual announcements. Existing
-- SELECT policies (including student Realtime access) continue to apply.
create policy "Manual announcements require staff and a running meeting"
on public.notifications as restrictive for insert to public
with check (
  kind <> 'custom' or (
    (select auth.uid()) is not null
    and exists (select 1 from public.meetings where status = 'running')
  )
);
