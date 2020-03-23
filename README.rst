pg_utils
========

Description
-----------
Tools, scripts and utilities, related to PostgreSQL.

Components
----------

rename_index.sql:
    A function, allowing concurrent index rename without *Exclusive Lock* of the table for versions before PostgreSQL 12.
