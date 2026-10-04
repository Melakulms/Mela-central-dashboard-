-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812215939
alter table public.proctor_audit_logs drop constraint if exists proctor_event_type_chk;
alter table public.proctor_audit_logs add constraint proctor_event_type_chk check (
  event_type is null or event_type in (
    'camera_permission','identity_check','face_check','tab_switch','visibility_change','session_summary',
    'face_presence_client','tab_hidden','tab_visible','fullscreen_exit','fullscreen_enter','window_blur','window_focus','network_change'
  )
);

;
