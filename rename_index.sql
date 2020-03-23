-- concurrent index rename for PostgreSQL < 12

CREATE FUNCTION rename_index(old_idx regclass, new_idx name, timeout int = 1000) RETURNS boolean AS $$
DECLARE
  parent_table regclass;
BEGIN
  PERFORM set_config('lock_timeout', $3::text, true);

  SELECT
    indrelid::regclass
  FROM
    pg_catalog.pg_index
  WHERE
    indexrelid = $1
  INTO
    parent_table;

  IF NOT FOUND THEN
    RAISE NOTICE 'index not found';
    RETURN false;
  END IF;

  EXECUTE FORMAT('LOCK TABLE %s IN SHARE UPDATE EXCLUSIVE MODE', parent_table);

  EXECUTE FORMAT('UPDATE pg_catalog.pg_class SET relname = %L WHERE oid = $1', $2) USING $1;

  PERFORM NULL FROM pg_catalog.pg_depend WHERE objid = $1 AND deptype = 'i';

  IF FOUND THEN
    EXECUTE FORMAT('UPDATE pg_catalog.pg_constraint SET conname = %L WHERE conindid = $1', $2) USING $1;
    RAISE NOTICE 'rename cascades to constraint %', $1;
  END IF;

  RETURN true;
EXCEPTION
  WHEN lock_not_available THEN
    RAISE NOTICE 'lock timeout';
    RETURN false;
  WHEN unique_violation THEN
    RAISE NOTICE 'relation "%" already exists', $2;
    RETURN false;
END
$$ LANGUAGE plpgsql;
