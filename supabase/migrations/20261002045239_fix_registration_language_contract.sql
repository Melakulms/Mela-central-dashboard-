do $migration$
declare definition text; marker text := '  v_requested_role := lower(trim(coalesce(new.raw_user_meta_data ->> ''role'','''')));';
begin
  select pg_get_functiondef('private.handle_new_auth_user()'::regprocedure) into definition;
  if strpos(definition, marker) = 0 then raise exception 'Unexpected signup trigger definition; review before applying'; end if;
  execute replace(definition, marker,
    '  select l.language_name into v_lang from public.platform_languages l where l.language_code=v_lang and l.enabled limit 1;' || chr(10) ||
    '  v_lang := coalesce(v_lang, ''English'');' || chr(10) || marker);
end $migration$;
