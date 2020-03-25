pg_utils
========

Description
-----------
Tools, scripts and utilities, related to PostgreSQL.

Components
----------

rename_index.sql:
    Concurrent index rename without *Exclusive Lock* of the table for versions before PostgreSQL 12.

rename_database.sql:
    Quick rename of a database (kill connections that might be stuck).
