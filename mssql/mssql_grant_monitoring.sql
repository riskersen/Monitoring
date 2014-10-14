declare @dbname varchar(255)
declare @check_mssql_health_USER varchar(255)
declare @check_mssql_health_PASS varchar(255)
declare @check_mssql_health_ROLE varchar(255)
declare @source varchar(255)
declare @options varchar(255)
declare @backslash int

/*******************************************************************/
SET @check_mssql_health_USER = '"MDKN\dbsnmp"'
SET @check_mssql_health_PASS = '_nur4MSSQL#Nagios_'
SET @check_mssql_health_ROLE = 'Monitoring'
/*******************************************************************

PLEASE CHANGE THE ABOVE VALUES ACCORDING TO YOUR REQUIREMENTS

- Example for Windows authentication:
  SET @check_mssql_health_USER = '"[Servername|Domainname]\Username"'
  SET @check_mssql_health_ROLE = 'Rolename'

- Example for SQL Server authentication:
  SET @check_mssql_health_USER = 'Username'
  SET @check_mssql_health_PASS = 'Password'
  SET @check_mssql_health_ROLE = 'Rolename'

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
It is strongly recommended to use Windows authentication. Otherwise
you will get no reliable results for database usage.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

*********** NO NEED TO CHANGE ANYTHING BELOW THIS LINE *************/

SET @options = 'DEFAULT_DATABASE=MASTER, DEFAULT_LANGUAGE=English'
SET @backslash = (SELECT CHARINDEX('\', @check_mssql_health_USER))
IF @backslash > 0
  BEGIN
    SET @source = ' FROM WINDOWS'
    SET @options = ' WITH ' + @options
  END
ELSE
  BEGIN
    SET @source = ''
    SET @options = ' WITH PASSWORD=''' + @check_mssql_health_PASS + ''',' + @options
  END

PRINT 'create Nagios plugin user ' + @check_mssql_health_USER
EXEC ('CREATE LOGIN ' + @check_mssql_health_USER + @source + @options)
EXEC ('USE MASTER GRANT VIEW SERVER STATE TO ' + @check_mssql_health_USER)
EXEC ('USE MASTER GRANT ALTER trace TO ' + @check_mssql_health_USER)
EXEC ('USE MSDB GRANT SELECT ON sysjobhistory TO ' + @check_mssql_health_USER)
EXEC ('USE MSDB GRANT SELECT ON sysjobschedules TO ' + @check_mssql_health_USER)
EXEC ('USE MSDB GRANT SELECT ON sysjobs TO ' + @check_mssql_health_USER)
PRINT 'User ' + @check_mssql_health_USER + ' created.'
PRINT ''

declare dblist cursor for
  select name from sysdatabases WHERE name NOT IN ('master', 'tempdb', 'msdb') open dblist
    fetch next from dblist into @dbname
    while @@fetch_status = 0 begin
      EXEC ('USE [' + @dbname + '] print ''GRANT permissions IN the db '' + ''"'' + DB_NAME() + ''"''')
      EXEC ('USE [' + @dbname + '] CREATE ROLE ' + @check_mssql_health_ROLE)
      EXEC ('USE [' + @dbname + '] GRANT EXECUTE TO ' + @check_mssql_health_ROLE)
      EXEC ('USE [' + @dbname + '] GRANT VIEW DATABASE STATE TO ' + @check_mssql_health_ROLE)
      EXEC ('USE [' + @dbname + '] GRANT VIEW DEFINITION TO ' + @check_mssql_health_ROLE)
      EXEC ('USE [' + @dbname + '] CREATE USER ' + @check_mssql_health_USER + ' FOR LOGIN ' + @check_mssql_health_USER)
      EXEC ('USE [' + @dbname + '] EXEC sp_addrolemember ' + @check_mssql_health_ROLE + ' , ' + @check_mssql_health_USER)
      EXEC ('USE [' + @dbname + '] print ''Permissions IN the db '' + ''"'' + DB_NAME() + ''" GRANTED.''')
      fetch next from dblist into @dbname
    end
close dblist
deallocate dblist