-- to be launched from another database

CREATE FUNCTION rename_database(old_name name, new_name name) RETURNS void AS $$
DECLARE
  conx bigint;
BEGIN
  RAISE NOTICE 'forbid connections';
  UPDATE pg_database SET datallowconn = false WHERE datname = $1;

  SELECT
    COUNT(pg_terminate_backend(pid))
  FROM
    pg_stat_activity
  WHERE
    datname = $1
  INTO
    conx;

  RAISE NOTICE 'killed % connection(s)', conx;

  RAISE NOTICE 'rename database';
  EXECUTE FORMAT('ALTER DATABASE %I RENAME TO %I', $1, $2);

  RAISE NOTICE 'allow connections';
  UPDATE pg_database SET datallowconn = true WHERE datname = $2;
END
$$ LANGUAGE plpgsql;
