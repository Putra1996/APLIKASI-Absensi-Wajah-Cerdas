-- =====================================================================
-- SD NEGERI KLUMPRIT 04 NUSAWUNGU — SUPABASE SECURE BASELINE
-- =====================================================================
-- Jalankan pada project Supabase KHUSUS sekolah di SQL Editor.
-- Skrip ini menolak akses anon, mengharuskan akun Supabase Auth yang
-- terdaftar di public.school_staff, menyimpan foto di bucket PRIVATE,
-- dan memisahkan template wajah dari roster siswa.
--
-- PENTING UNTUK UPGRADE DARI VERSI DEMO:
-- * Versi demo membuka akses anon dan memakai bucket publik. Anggap data
--   demo mungkin telah diakses pihak lain. Jangan pindahkan data biometrik
--   tanpa dasar/persetujuan yang terdokumentasi.
-- * Skrip ini menghapus kolom lama students.face_descriptor dan mengosongkan
--   photo_url lama yang belum memiliki bukti persetujuan di skema baru.
--   Siswa lama tetap ada sebagai roster manual. Objek foto lama di Storage
--   TIDAK dihapus skrip ini: hapus objek student-photos lama melalui
--   Supabase Dashboard → Storage setelah meninjau kebutuhan retensi.
-- * Skrip tidak menghapus attendance lama. Jika project pernah dipakai demo,
--   tinjau/hapus log lama sebelum go-live; kolom method lama akan bernilai
--   'Legacy' dan tidak dianggap sebagai absensi sah oleh aplikasi.
--
-- Langkah pertama admin setelah skrip:
-- 1. Buat akun petugas melalui Authentication → Users. Matikan public sign-up.
-- 2. Ambil UUID akun admin, kemudian jalankan query contoh di README.md untuk
--    memasukkannya ke school_staff sebagai role 'admin'.
-- 3. Buat akun petugas lain dengan role 'teacher'. Jangan berikan service_role
--    key ke aplikasi/browser.
-- =====================================================================

create extension if not exists pgcrypto;

-- 1. Roster minim-data: foto hanya disimpan bila consent biometrik terverifikasi.
create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  nisn text not null unique,
  name text not null,
  class_name text not null,
  photo_url text, -- path object privat di bucket student-photos; bukan URL publik
  consent_confirmed boolean not null default false,
  consent_confirmed_at timestamptz,
  consent_confirmed_by uuid references auth.users(id),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  constraint students_nisn_not_empty check (length(trim(nisn)) > 0),
  constraint students_name_not_empty check (length(trim(name)) > 0),
  constraint students_class_not_empty check (length(trim(class_name)) > 0),
  constraint students_consent_consistent check (
    (consent_confirmed = false and consent_confirmed_at is null and consent_confirmed_by is null and photo_url is null)
    or
    (consent_confirmed = true and consent_confirmed_at is not null and consent_confirmed_by is not null and photo_url is not null)
  )
);

-- Tambahan kolom untuk project demo yang sudah memiliki tabel students.
alter table public.students add column if not exists photo_url text;
alter table public.students add column if not exists consent_confirmed boolean not null default false;
alter table public.students add column if not exists consent_confirmed_at timestamptz;
alter table public.students add column if not exists consent_confirmed_by uuid references auth.users(id);
alter table public.students add column if not exists created_by uuid references auth.users(id) on delete set null default auth.uid();
alter table public.students add column if not exists created_at timestamptz not null default now();

-- Descriptor demo tidak mempunyai bukti consent. Hapus dari tabel lama, bukan
-- menganggap checkbox baru sebagai persetujuan retroaktif.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'students' and column_name = 'face_descriptor'
  ) then
    execute 'alter table public.students drop column face_descriptor';
  end if;
end
$$;

-- Foto lama pada versi demo tidak punya consent terverifikasi; putuskan referensi.
update public.students
set photo_url = null,
    consent_confirmed = false,
    consent_confirmed_at = null,
    consent_confirmed_by = null
where consent_confirmed = false;

create unique index if not exists students_nisn_case_insensitive_uidx
  on public.students (lower(nisn));
create index if not exists students_class_name_idx
  on public.students (class_name);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'students_consent_consistent') then
    alter table public.students add constraint students_consent_consistent check (
      (consent_confirmed = false and consent_confirmed_at is null and consent_confirmed_by is null and photo_url is null)
      or
      (consent_confirmed = true and consent_confirmed_at is not null and consent_confirmed_by is not null and photo_url is not null)
    );
  end if;
end
$$;

-- 2. Template wajah terpisah; hanya dibuat melalui RPC setelah petugas
-- menyatakan persetujuan tertulis orang tua/wali telah diverifikasi.
create table if not exists public.student_face_templates (
  student_id uuid primary key references public.students(id) on delete cascade,
  face_descriptor jsonb not null,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  constraint face_descriptor_128 check (
    case
      when jsonb_typeof(face_descriptor) = 'array'
        then jsonb_array_length(face_descriptor) = 128
      else false
    end
  )
);

-- 3. Daftar petugas adalah allowlist yang hanya dikelola melalui SQL Editor.
create table if not exists public.school_staff (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role text not null check (role in ('admin', 'teacher')),
  class_names text[] not null default '{}', -- teacher hanya boleh mengakses kelas yang ditugaskan
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint school_staff_name_not_empty check (length(trim(full_name)) > 0)
);
alter table public.school_staff add column if not exists class_names text[] not null default '{}';

create or replace function public.is_school_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.school_staff ss
    where ss.user_id = (select auth.uid()) and ss.is_active = true
  );
$$;

create or replace function public.is_school_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.school_staff ss
    where ss.user_id = (select auth.uid()) and ss.is_active = true and ss.role = 'admin'
  );
$$;

create or replace function public.can_access_class(p_class_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.school_staff ss
    where ss.user_id = (select auth.uid())
      and ss.is_active = true
      and (ss.role = 'admin' or p_class_name = any(ss.class_names))
  );
$$;

revoke all on function public.is_school_staff() from public, anon;
revoke all on function public.is_school_admin() from public, anon;
revoke all on function public.can_access_class(text) from public, anon;
grant execute on function public.is_school_staff() to authenticated;
grant execute on function public.is_school_admin() to authenticated;
grant execute on function public.can_access_class(text) to authenticated;

-- 4. Catatan presensi: cap tanggal/jam dan kelas dibuat database, bukan jam
-- laptop klien. Waktu sekolah dipatok ke Asia/Jakarta.
create table if not exists public.attendances (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  class_name text not null,
  date date not null default ((timezone('Asia/Jakarta', now()))::date),
  time time not null default ((timezone('Asia/Jakarta', now()))::time),
  status text not null default 'Hadir',
  method text not null default 'Legacy',
  recorded_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  constraint attendances_student_date_unique unique (student_id, date),
  constraint attendances_status_hadir check (status = 'Hadir'),
  constraint attendances_method_valid check (method in ('Wajah', 'Manual', 'Legacy'))
);

alter table public.attendances add column if not exists method text not null default 'Legacy';
alter table public.attendances add column if not exists recorded_by uuid references auth.users(id) on delete set null default auth.uid();
alter table public.attendances add column if not exists created_at timestamptz not null default now();
create index if not exists attendances_date_idx on public.attendances (date);
create index if not exists attendances_class_date_idx on public.attendances (class_name, date);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'attendances_student_date_unique') then
    alter table public.attendances add constraint attendances_student_date_unique unique (student_id, date);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'attendances_status_hadir') then
    alter table public.attendances add constraint attendances_status_hadir check (status = 'Hadir');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'attendances_method_valid') then
    alter table public.attendances add constraint attendances_method_valid check (method in ('Wajah', 'Manual', 'Legacy'));
  end if;
end
$$;

create or replace function public.stamp_attendance()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  school_now timestamp;
  student_class text;
  student_has_biometric_consent boolean;
begin
  if not public.is_school_staff() then
    raise exception 'Petugas sekolah tidak terotorisasi' using errcode = '42501';
  end if;
  if new.method not in ('Wajah', 'Manual') then
    raise exception 'Metode presensi tidak valid' using errcode = '23514';
  end if;
  select s.class_name, s.consent_confirmed
    into student_class, student_has_biometric_consent
  from public.students s
  where s.id = new.student_id;
  if student_class is null then
    raise exception 'Siswa tidak ditemukan atau tidak dapat diakses' using errcode = '23503';
  end if;
  if not public.can_access_class(student_class) then
    raise exception 'Petugas tidak ditugaskan ke kelas siswa ini' using errcode = '42501';
  end if;
  if new.method = 'Wajah' and (
    student_has_biometric_consent is distinct from true
    or not exists (select 1 from public.student_face_templates t where t.student_id = new.student_id)
  ) then
    raise exception 'Presensi wajah tidak diizinkan untuk siswa ini' using errcode = '42501';
  end if;
  school_now := timezone('Asia/Jakarta', clock_timestamp());
  new.class_name := student_class;
  new.date := school_now::date;
  new.time := school_now::time;
  new.status := 'Hadir';
  new.recorded_by := (select auth.uid());
  return new;
end;
$$;

drop trigger if exists attendances_stamp_before_insert on public.attendances;
create trigger attendances_stamp_before_insert
before insert on public.attendances
for each row execute function public.stamp_attendance();

-- 5. RPC atomik untuk membuat roster + template wajah. SECURITY DEFINER dipakai
-- hanya untuk transaksi dua tabel; fungsi memeriksa allowlist dan semua objek
-- memakai nama schema penuh + search_path kosong.
create or replace function public.register_student_with_face(
  p_nisn text,
  p_name text,
  p_class_name text,
  p_face_descriptor jsonb,
  p_photo_path text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_student_id uuid;
  staff_id uuid := (select auth.uid());
begin
  if not public.is_school_staff() then
    raise exception 'Petugas sekolah tidak terotorisasi' using errcode = '42501';
  end if;
  if nullif(trim(p_nisn), '') is null or nullif(trim(p_name), '') is null or nullif(trim(p_class_name), '') is null then
    raise exception 'NISN, nama, dan kelas wajib diisi' using errcode = '23514';
  end if;
  if not public.can_access_class(trim(p_class_name)) then
    raise exception 'Petugas tidak ditugaskan ke kelas tersebut' using errcode = '42501';
  end if;
  if jsonb_typeof(p_face_descriptor) <> 'array' or jsonb_array_length(p_face_descriptor) <> 128 then
    raise exception 'Template wajah harus berupa array 128 angka' using errcode = '23514';
  end if;
  if p_photo_path is null or (storage.foldername(p_photo_path))[1] <> staff_id::text then
    raise exception 'Path foto bukan milik petugas yang sedang login' using errcode = '42501';
  end if;

  insert into public.students (
    nisn, name, class_name, photo_url,
    consent_confirmed, consent_confirmed_at, consent_confirmed_by, created_by
  ) values (
    trim(p_nisn), trim(p_name), trim(p_class_name), p_photo_path,
    true, now(), staff_id, staff_id
  ) returning id into new_student_id;

  insert into public.student_face_templates (student_id, face_descriptor, created_by)
  values (new_student_id, p_face_descriptor, staff_id);

  return new_student_id;
end;
$$;

revoke all on function public.stamp_attendance() from public, anon;
grant execute on function public.stamp_attendance() to authenticated;
revoke all on function public.register_student_with_face(text, text, text, jsonb, text) from public, anon;
grant execute on function public.register_student_with_face(text, text, text, jsonb, text) to authenticated;

-- 6. Aktifkan RLS. Reset policy pada tabel aplikasi ini agar policy demo lama
-- tidak dapat tetap memberi akses anon lewat OR antar-policy PostgreSQL.
do $$
declare
  policy_row record;
begin
  for policy_row in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('students', 'student_face_templates', 'school_staff', 'attendances')
  loop
    execute format('drop policy if exists %I on %I.%I', policy_row.policyname, policy_row.schemaname, policy_row.tablename);
  end loop;
end
$$;

alter table public.students enable row level security;
alter table public.student_face_templates enable row level security;
alter table public.school_staff enable row level security;
alter table public.attendances enable row level security;

revoke all privileges on table public.students, public.student_face_templates, public.school_staff, public.attendances from anon, authenticated, public;
grant select, insert on table public.students to authenticated;
grant select on table public.student_face_templates to authenticated;
grant select on table public.school_staff to authenticated;
grant select, insert on table public.attendances to authenticated;

create policy staff_read_students
  on public.students for select to authenticated
  using ((select public.can_access_class(class_name)));
create policy staff_add_manual_roster
  on public.students for insert to authenticated
  with check (
    (select public.can_access_class(class_name))
    and created_by = (select auth.uid())
    and consent_confirmed = false
    and consent_confirmed_at is null
    and consent_confirmed_by is null
    and photo_url is null
  );

create policy staff_read_face_templates_with_consent
  on public.student_face_templates for select to authenticated
  using (
    (select public.is_school_staff())
    and exists (
      select 1 from public.students s
      where s.id = student_face_templates.student_id
        and s.consent_confirmed = true
        and public.can_access_class(s.class_name)
    )
  );

create policy staff_read_school_staff
  on public.school_staff for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_school_admin()));

create policy staff_read_attendances
  on public.attendances for select to authenticated
  using ((select public.can_access_class(class_name)));
create policy staff_insert_attendances
  on public.attendances for insert to authenticated
  with check (
    (select public.can_access_class(class_name))
    and recorded_by = (select auth.uid())
    and method in ('Wajah', 'Manual')
  );

-- 7. Bucket foto privat. Prefix folder wajib UUID petugas pengunggah.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('student-photos', 'student-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']::text[])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Hilangkan grant dan policy anon dari bucket demo. Project Supabase ini
-- sebaiknya khusus untuk aplikasi sekolah karena storage.objects dipakai bersama.
drop policy if exists "demo_anon_read_student_photos" on storage.objects;
drop policy if exists "demo_anon_upload_student_photos" on storage.objects;
drop policy if exists school_staff_read_student_photos on storage.objects;
drop policy if exists school_staff_upload_own_student_photos on storage.objects;
drop policy if exists school_staff_delete_own_or_admin_photos on storage.objects;
alter table storage.objects enable row level security;
revoke all privileges on table storage.objects from anon, authenticated, public;
grant select, insert, delete on table storage.objects to authenticated;

create policy school_staff_read_student_photos
  on storage.objects for select to authenticated
  using (
    bucket_id = 'student-photos'
    and (select public.is_school_staff())
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or exists (
        select 1 from public.students s
        where s.photo_url = storage.objects.name
          and public.can_access_class(s.class_name)
      )
    )
  );
create policy school_staff_upload_own_student_photos
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'student-photos'
    and (select public.is_school_staff())
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
create policy school_staff_delete_own_or_admin_photos
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'student-photos'
    and (select public.is_school_staff())
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or (select public.is_school_admin())
    )
  );

-- 8. Realtime insert log kehadiran. RLS tetap memfilter berdasarkan staff login.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'attendances'
     ) then
    execute 'alter publication supabase_realtime add table public.attendances';
  end if;
end
$$;

-- =====================================================================
-- Bootstrap admin dilakukan setelah membuat user Auth. Contoh (ubah email):
--
-- insert into public.school_staff (user_id, full_name, role, class_names)
-- select id, 'Admin SD Negeri Klumprit 04 Nusawungu', 'admin', '{}'
-- from auth.users where email = 'EMAIL_ADMIN_YANG_DIBUAT_DI_AUTH';
--
-- Teacher hanya diberi kelas yang ditugaskan (sesuaikan nama kelas persis):
-- insert into public.school_staff (user_id, full_name, role, class_names)
-- select id, 'Nama Petugas', 'teacher', array['IV-A', 'IV-B']::text[]
-- from auth.users where email = 'EMAIL_PETUGAS';
-- =====================================================================
