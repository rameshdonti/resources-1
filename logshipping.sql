

use [master]
set nocount on
go
-- ====================================================================================
--
--  Create database if it does not already exist...
--
CREATE DATABASE [YuanCustomLogShippingAdmin]
 CONTAINMENT = NONE
 ON  PRIMARY 
( NAME = N'YuanCustomLogShippingAdmin', FILENAME = N'D:\Data01\MSSQL12.OTC\MSSQL\DATA\YuanCustomLogShippingAdmin' , SIZE = 5120KB , FILEGROWTH = 10%)
 LOG ON 
( NAME = N'YuanCustomLogShippingAdmin_log', FILENAME = N'D:\Data01\YuanCustomLogShippingAdmin.LDF' , SIZE = 2048KB , FILEGROWTH = 10%)
GO

ALTER DATABASE [YuanCustomLogShippingAdmin] SET TRUSTWORTHY OFF;
go

-- ====================================================================================
--
-- now create DB objects (if they dont already exist)

Use YuanCustomLogShippingAdmin
go


IF NOT EXISTS (SELECT * FROM sys.objects WHERE name = 'tblMigrationRoutineVersion')
BEGIN
	CREATE TABLE [dbo].[tblMigrationRoutineVersion]
	(
		[Version]				sysname			NOT NULL PRIMARY KEY,
		InstallDate				datetime		not null default (getdate())
	)
END;
go

declare @Version sysname = '1.2';
update dbo.[tblMigrationRoutineVersion]
set Version= @Version, InstallDate = getdate();

if @@rowcount = 0
	insert into dbo.[tblMigrationRoutineVersion] (Version, InstallDate)
	values (@Version, getdate())
go

-- ====================================================================================
-- drop table tblMigrationDatabases

IF NOT EXISTS (SELECT * FROM sys.objects WHERE name = 'tblMigrationDatabases')
BEGIN
	CREATE TABLE [dbo].[tblMigrationDatabases]
	(
		[MigrationDatabaseName]				sysname			NOT NULL,
		[SourceDBServer]					varchar(150)	NOT NULL,
		[SourceDBName] 						sysname			NOT NULL,
		[DestinationDBName] 				sysname			NULL,		-- NULL means the same as the Source DB Name
		[SourceLogBackupFolderUNC]			varchar(500)	NOT NULL,	-- e.g. \\<server>\f$\MSSQL$OLTP\MSSQL.1\MSSQL\BACKUP\Lendfast_EVA
		[SourceLogBackupFileNameTemplate]	varchar(500)	NOT NULL,	-- e.g. <dbname>*LOG*.TRN
		[DesitnationLogBackupFolderName]	varchar(500)	NOT NULL,	-- e.g. d:\BACKUP01\TransferBackups\<dbname>
		[RestoreUsingLiteSpeed]				char(1)			NOT NULL default ('Y') check (RestoreUsingLiteSpeed in ('Y','N')),
		[RobocopyOptions]					varchar(500)	NOT NULL default (' /R:5 /W:10 '),	-- Specify any robocopy options you want
		[Credentials] 						varchar(500)	NULL,
		[RestoredUpToDate]					datetime		null,		-- system managed - dont set manually
		[FullDBBackupFinishDate]				datetime		null,		-- system managed - dont set manually
		[FullDBRestoreDate]					datetime		null,		-- system managed - dont set manually
		[OverrideLoggingFolder]				varchar(1000)	null,		-- Defaults to the SQL instance Log folder. Can override this here
		CONSTRAINT [UQ_tblMigrationDatabases_1] UNIQUE
		(
			[SourceDBServer] ASC,
			[SourceDBName] ASC
		),
		CONSTRAINT [PK_tblMigrationDatabases] PRIMARY KEY CLUSTERED 
		(
			[MigrationDatabaseName]
		)
	) 
END
-- in v1.2 we renamed a column.
if exists (select 1 from sys.columns where object_id = object_id('dbo.tblMigrationDatabases') and name = 'FullDBBackupStartDate')
begin
	exec sp_rename 'dbo.tblMigrationDatabases.FullDBBackupStartDate', 'FullDBBackupFinishDate' , 'COLUMN'

end

GO

-- ====================================================================================
-- drop table [tblCustomLogShippingRuns]


IF NOT EXISTS (SELECT * FROM sys.objects WHERE name = 'tblCustomLogShippingRuns')
BEGIN
	CREATE TABLE [dbo].[tblCustomLogShippingRuns]
	(
		[RunId] 							int identity primary key clustered,
		[RunStatus]							varchar(20)		NOT NULL,
		[MigrationDatabaseName]				sysname			NOT NULL,
		[RunStartTime]						datetime		NOT NULL,
		[RunEndTime]						datetime		NULL,
		[FilesFound]						int				NOT NULL,
		[FilesRestored]						int				NOT NULL,
		[RunDurationSeconds]				as (datediff(s, [RunStartTime], [RunEndTime])),
		[MapDriveDurationSeconds]			int				null,
		[RoboCopyDurationSeconds]			int				null,
		[FindFilesDurationSeconds]			int				null,
		[RestoreDurationSeconds]			int				null,
		[RunUserid]							varchar(100)	null default (suser_sname()),
		[RunProgram]						varchar(100)	null default (program_name()),
		[RunSIPD]							int				null default (@@spid),
		[RunClientHost]						varchar(100)	null default(host_name())

	) 
/*
	alter  TABLE [dbo].[tblCustomLogShippingRuns] add
		[RunDurationSeconds]				as (datediff(s, [RunStartTime], [RunEndTime]) )
		
*/
/*
	alter  TABLE [dbo].[tblCustomLogShippingRuns] add
		[RunUserid]							varchar(100)	null default (suser_sname()),
		[RunProgram]						varchar(100)	null default (program_name()),
		[RunSIPD]							int				null default (@@spid),
		[RunClientHost]						varchar(100)	null default(host_name())
*/
/*
	alter  TABLE [dbo].[tblCustomLogShippingRuns] add
		[MapDriveDurationSeconds]			int null,
		[RoboCopyDurationSeconds]			int null,
		[RestoreDurationSeconds]			int null
alter  TABLE [dbo].[tblCustomLogShippingRuns] add
		[FindFilesDurationSeconds]			int				null
		
*/
END
GO
-- ====================================================================================
-- drop table tblMigrationDatabaseLogBackups

IF NOT EXISTS (SELECT * FROM sys.objects WHERE name = 'tblMigrationDatabaseLogBackups')
BEGIN
	CREATE TABLE [dbo].[tblMigrationDatabaseLogBackups]
	(
		[MigrationDatabaseName]		sysname			NOT NULL,
		[LogBackupFileName]			varchar(500)	NOT NULL,

		[LogBackupFolder]			varchar(500)	NOT NULL,
		[BackupFileDate]			datetime		NOT NULL,
		[BackupFileSize]			bigint			NOT NULL,
		[RestoreStatus]				varchar(20)		NOT NULL DEFAULT ('Not Started') CHECK (RestoreStatus in ('Not Started', 'Running', 'Completed', 'Failed', 'Not Required')),
		[RestoreStart]				datetime		NULL,
		[RestoreFinish]				datetime		NULL,
		[FoundByRunId]				int				NOT NULL,
		[RestoredByRunId]			int				NULL,
		 CONSTRAINT [PK_tblMigrationDatabaseLogBackups] PRIMARY KEY CLUSTERED 
		(
			[MigrationDatabaseName]	ASC,
			[LogBackupFileName]		ASC
		),
		 CONSTRAINT [FK_tblMigrationDatabaseLogBackups] FOREIGN KEY ([MigrationDatabaseName])
				REFERENCES dbo.tblMigrationDatabases ([MigrationDatabaseName])
	)
END
GO

-- ====================================================================================
 -- drop table tblMigrationDatabaseAdditionalRobocopyOptions

IF EXISTS (SELECT * FROM sys.objects WHERE name = 'tblMigrationDatabaseAdditionalRobocopyOptions')
BEGIN
	drop table tblMigrationDatabaseAdditionalRobocopyOptions
END
GO

-- drop table tblMessageLog

IF NOT EXISTS (SELECT * FROM sys.objects WHERE name = 'tblMessageLog')
BEGIN
	CREATE TABLE [dbo].[tblMessageLog]
	(
		[MessageDateTime] datetime NOT NULL default (Getdate()),
		[MessageText] varchar(1000) NOT NULL,
		[MessageType] varchar(10) NOT NULL DEFAULT ('Info'),
		[ProcName] sysname NULL,
		[SPID] int NOT NULL DEFAULT (@@spid),
		[UserName] sysname NOT NULL DEFAULT (suser_sname()) ,
		[ApplicationName] varchar(255) NULL DEFAULT (app_name()),
		[HostName] varchar(50) NULL DEFAULT (host_name()),
		[RunId] int NULL,
		[LogId] int IDENTITY(1,1) NOT NULL,
		CONSTRAINT [PK_tblHistoryRecord] PRIMARY KEY CLUSTERED 
		(
			[LogId] ASC
		)
	) 
END
GO

-- ===========================================================================
if not exists (select * from sys.objects where name = 'prc_RaiseError')
begin
	exec ('CREATE PROC dbo.prc_RaiseError as print ''Dummy proc''; ');
end
go
ALTER PROCEDURE [dbo].[prc_RaiseError]
(
 @MessageText 	varchar(1000),
 @ProcId		int		= null,
 @ArgCnt 		tinyint 	= 0,
 @ReplArg1		varchar(1000)	= NULL,
 @ReplArg2		varchar(1000)	= NULL,
 @ReplArg3 		varchar(1000)	= NULL,
 @ReplArg4 		varchar(1000)	= NULL,
 @ReplArg5		varchar(1000) 	= NULL,
 @InfoOnly 		bit 		= 0,		 --Default to Critical Error
 @MessageType	varchar(10) 	= null,
 @SuppressErrorLogging bit 	= 1,		-- suppress writing the error message to the SQL Log?
 @RunId			int  = null
)
AS
--
--  Generic message and error logging proc.
--  Based on the DBAdmin proc of the same name.
--
--


set nocount on

DECLARE @MessageStr varchar(1000), 
	@i int, 
	@AddedFilesCnt int, 
	@MessageStr2 varchar(1000),
	@MessageStr3 varchar(1000)
if len(@MessageText) > 900
	set @MessageText = substring(@MessageText, 1, 900) + '<msg truncated>';
if len(@ReplArg1) > 500
	set @ReplArg1 = substring(@ReplArg1, 1, 500) + '<truncated>';
if len(@ReplArg2) > 500
	set @ReplArg2 = substring(@ReplArg2, 1, 500) + '<truncated>';
if len(@ReplArg3) > 500
	set @ReplArg3 = substring(@ReplArg3, 1, 500) + '<truncated>';
if @MessageText is null
	select @MessageText = '<<Null Message passed to ' + object_name(@@procid) + '>>'
set @MessageText = REPLICATE('  ', @@nestlevel - 2) + + @MessageText

select @MessageStr = @MessageText,
	@MessageStr2 = @MessageText
IF @ArgCnt > 5
BEGIN
	set @MessageStr = 'Error: Maximum of 5 Replacement Arguments Allowed'
	print @MessageStr 
	raiserror (@MessageStr, 16, 16)
	RETURN (-1)
END
SELECT @ReplArg1 = ISNULL(@ReplArg1,'')
SELECT @ReplArg2 = ISNULL(@ReplArg2,'')
SELECT @ReplArg3 = ISNULL(@ReplArg3,'')
SELECT @ReplArg4 = ISNULL(@ReplArg4,'')
SELECT @ReplArg5 = ISNULL(@ReplArg5,'')

if @MessageType is null
begin
	if @InfoOnly = 1
		select @MessageType = 'Info'
	else
		select @MessageType = 'Error'
end

--  cant find an equivilent string substitution
--  so we have to do it ourselves.
	
select @i = charindex('%s', @MessageStr2),
	@AddedFilesCnt = 0
while @i > 0
begin
	select @AddedFilesCnt = @AddedFilesCnt + 1
	select @MessageStr2 = stuff(@MessageStr2, @i, 2,
				case @AddedFilesCnt
					when 1 then @ReplArg1
					when 2 then @ReplArg2
					when 3 then @ReplArg3
					when 4 then @ReplArg4
					when 5 then @ReplArg5
				end)
	select @i = charindex('%s', @MessageStr2)
end

IF @InfoOnly = 0
BEGIN 
	set @MessageStr = ltrim(@MessageStr)
	if @SuppressErrorLogging = 0
	begin
		IF @ArgCnt = 0
			RAISERROR (@MessageStr,16, 1) WITH LOG, NOWAIT
		IF @ArgCnt = 1
			RAISERROR (@MessageStr,16, 1,@ReplArg1) WITH LOG, NOWAIT
		IF @ArgCnt = 2
			RAISERROR (@MessageStr,16, 1,@ReplArg1,@ReplArg2) WITH LOG, NOWAIT
		IF @ArgCnt = 3
			RAISERROR (@MessageStr,16, 1,@ReplArg1,@ReplArg2,@ReplArg3) WITH LOG, NOWAIT
		IF @ArgCnt = 4
			RAISERROR (@MessageStr,16, 1,@ReplArg1,@ReplArg2,@ReplArg3,@ReplArg4) WITH LOG, NOWAIT
		IF @ArgCnt = 5
			RAISERROR (@MessageStr,16, 1,@ReplArg1,@ReplArg2,@ReplArg3,@ReplArg4,@ReplArg5) WITH LOG, NOWAIT
	end
	else -- @SuppressErrorLogging = 1
	begin
		IF @ArgCnt = 0
			RAISERROR (@MessageStr,16, 1) WITH NOWAIT
		IF @ArgCnt = 1
			RAISERROR (@MessageStr,16, 1,@ReplArg1) WITH NOWAIT
		IF @ArgCnt = 2
			RAISERROR (@MessageStr,16, 1,@ReplArg1,@ReplArg2) WITH NOWAIT
		IF @ArgCnt = 3
			RAISERROR (@MessageStr,16, 1,@ReplArg1,@ReplArg2,@ReplArg3) WITH NOWAIT
		IF @ArgCnt = 4
			RAISERROR (@MessageStr,16, 1,@ReplArg1,@ReplArg2,@ReplArg3,@ReplArg4) WITH NOWAIT
		IF @ArgCnt = 5
			RAISERROR (@MessageStr,16, 1,@ReplArg1,@ReplArg2,@ReplArg3,@ReplArg4,@ReplArg5) WITH NOWAIT
	end
	print convert(varchar(30),getdate(),120) + ': ' + replicate('*', 80)

	print convert(varchar(30),getdate(),120) + ': * ' + @MessageStr2
	print convert(varchar(30),getdate(),120) + ': ' + replicate('*', 80)
END
else
begin
	set @MessageStr3 = convert(varchar(30),getdate(),120) + ': ' + @MessageStr2
	raiserror (@MessageStr3, 0, 1) WITH NOWAIT
	--print convert(varchar(30),getdate(),120) + ': ' + @MessageStr2
end
	

insert into dbo.tblMessageLog
(MessageDateTime, MessageText, MessageType, ProcName, UserName, ApplicationName, HostName, RunId)
select getdate(), @MessageStr2, @MessageType, object_name(@ProcId), suser_sname(), rtrim(app_name()), rtrim(host_name()), @RunId



go


-- ===========================================================================
if exists (select * from sys.objects where name = 'prc_GetFileDetails')
begin
	exec ('DROP PROC dbo.prc_GetFileDetails; ');
end
if exists ( select 1 from sys.assemblies where name = 'asm_GetFileDetails')
	drop ASSEMBLY [asm_GetFileDetails]
go
go



-- ===========================================================================
if not exists (select * from sys.objects where name = 'prc_CopyLogFiles')
begin
	exec ('CREATE PROC dbo.prc_CopyLogFiles as print ''Dummy proc''; ');
end
go
alter PROCEDURE [dbo].[prc_CopyLogFiles]
(
 @MigrationDatabaseName		sysname,
 @RunId						int
)
as
set nocount on;
declare @Msg								varchar(1000);
declare @Cmd								varchar(1000);
declare @Cmd2								varchar(1000);
declare @rc									int;
declare @AddedFilesCnt						int;
declare @SourceDBServer						varchar(150);
declare @SourceDBName 						sysname;
declare @DestinationDBName	 				sysname;
declare @BackupFileSizeKB					bigint;
declare @SourceLogBackupFolderUNC			varchar(500);
declare @SourceLogBackupFileNameTemplate	varchar(500);
declare @DesitnationLogBackupFolderName		varchar(500);
declare @Credentials						varchar(500);
declare @RobocopyOptions					varchar(500);
declare @AdditionalRobocopyOptions			varchar(500);
declare @BackupFileSize						bigint;
declare @BackupFileDate						datetime;
declare @FullDBBackupFinishDate				datetime;
declare @ThisFileName						varchar(1000);
declare @FullFileName						varchar(1000);
declare @tmp1								varchar(100);
declare @tmp2								varchar(100);
declare @tmp3								varchar(500);
declare @i									int;
declare @tmpDate							datetime;
declare @CmdOutputLine						varchar(1000);
declare @TmpFileName						varchar(100) = '<masterfolder>\Robocopy_<SQLName>_<dbname>_<datetime>.txt';
declare @CmdOutput table
(
	CmdOutputLine							varchar(1000) null,
	id										bigint identity primary key clustered
)
declare @CmdOutput2 table
(
	CmdOutputLine							varchar(1000) null,
	id										bigint identity primary key clustered
)
declare @ThisProc							sysname;
set @ThisProc = object_name(@@procid);
set @TmpFileName = replace (@TmpFileName, '<SQLName>', replace(@@servername, '\', '_'))
set @TmpFileName = replace (@TmpFileName, '<dbname>', @MigrationDatabaseName)
set @TmpFileName = replace (@TmpFileName, '<datetime>', convert(varchar(20),getdate(),112) + replace(convert(varchar(20),getdate(),108),':',''))
set @tmp3 = null

exec dbo.prc_RaiseError ' ', @@procid, @InfoOnly=1, @RunId=@RunId
exec dbo.prc_RaiseError '%s started with migration DB name ''%s''.', @@procid, 2, @ThisProc,@MigrationDatabaseName, @InfoOnly=1, @RunId=@RunId

select	@SourceDBServer						= SourceDBServer,
		@SourceDBName						= SourceDBName,
		@DestinationDBName					= isnull(DestinationDBName,SourceDBName),
		@SourceLogBackupFolderUNC			= SourceLogBackupFolderUNC,
		@SourceLogBackupFileNameTemplate	= SourceLogBackupFileNameTemplate,
		@DesitnationLogBackupFolderName		= DesitnationLogBackupFolderName,
		@RobocopyOptions					= RobocopyOptions,
		@Credentials 						= [Credentials],
		@tmp3								= OverrideLoggingFolder,
		@FullDBBackupFinishDate				= FullDBBackupFinishDate
from dbo.tblMigrationDatabases
where MigrationDatabaseName = @MigrationDatabaseName

if @@rowcount = 0
begin
	exec dbo.prc_RaiseError 'ERROR in proc %s: No record exists in table tblMigrationDatabases with MigrationDatabaseName=''%s''.', @@procid, 2, @ThisProc,@MigrationDatabaseName, @RunId=@RunId
	return 1
end


if @tmp3 is null
	select @tmp3 = replace(lower(physical_name),'\data\master.mdf','') + '\log' from master.sys.database_files where name = 'master'
set @TmpFileName = replace (@TmpFileName, '<masterfolder>', @tmp3)


set @SourceLogBackupFolderUNC = replace(@SourceLogBackupFolderUNC, '<server>', @SourceDBServer)
set @SourceLogBackupFolderUNC = replace(@SourceLogBackupFolderUNC, '<dbname>', @SourceDBName)

set @DesitnationLogBackupFolderName = replace(@DesitnationLogBackupFolderName, '<server>', @SourceDBServer)
set @DesitnationLogBackupFolderName = replace(@DesitnationLogBackupFolderName, '<dbname>', @SourceDBName)

set @SourceLogBackupFileNameTemplate = replace(@SourceLogBackupFileNameTemplate, '<server>', @SourceDBServer)
set @SourceLogBackupFileNameTemplate = replace(@SourceLogBackupFileNameTemplate, '<dbname>', @SourceDBName)



if isnull(@Credentials,'') <> ''
begin
	set @tmpDate = getdate();
	
	exec dbo.prc_RaiseError 'Issuing NET USE to remote UNC: %s', @@procid, 1, @SourceLogBackupFolderUNC, @InfoOnly=1, @RunId=@RunId

	set @Cmd = 'net use "' + @SourceLogBackupFolderUNC + '" /persistent:no'
	if @Credentials <> 'none'
		set @Cmd = @Cmd + ' ' + @Credentials

	delete from @CmdOutput

	insert into @CmdOutput (CmdOutputLine)
	exec @rc = master.dbo.xp_cmdshell @Cmd
	
	if @rc <> 0
	begin
		exec dbo.prc_RaiseError 'NET USE command failed with rc %s. Command was: %s', @@procid, 2, @rc, @Cmd, @InfoOnly=1, @RunId=@RunId
		select * from @CmdOutput
		set @rc = 1
		goto ErrorHandler
	end

	set @i = datediff(s, @tmpDate, getdate());
	
	update  dbo.tblCustomLogShippingRuns
	set MapDriveDurationSeconds = @i
	where RunId = @RunId
end
--------------------------------------------------------------------
--
--  ROBOCOPY section - copy any new log backup files to the local folder
--

select @AdditionalRobocopyOptions = '';

-- exclude any log backup files that were produced in the 5 days before our full backup was taken
set @i = 5
while @i > 0
begin
	set @tmpDate = dateadd(d, 0 - @i, @FullDBBackupFinishDate)
	set @tmp1 = convert(char(8), @tmpDate, 112)	-- yyyymmdd

	-- exclude files that contain this date
	set @AdditionalRobocopyOptions = @AdditionalRobocopyOptions + ' /XF *' + @tmp1 + '*'
	set @rc = @@error;
	if @rc <> 0 goto ErrorHandler;
	set @i = @i - 1
end

-- exclude any log backup files that were produced on the day of out full backup, but before it was taken
set @i = 0
while @i < datepart(HH, @FullDBBackupFinishDate)
begin

	set @tmp1 = convert(char(8), @FullDBBackupFinishDate, 112) + right('00' + convert(varchar(2),@i) ,2) 	-- yyyymmdd

	-- exclude files that contain this date
	set @AdditionalRobocopyOptions = @AdditionalRobocopyOptions + ' /XF *' + @tmp1 + '*';
	set @rc = @@error;
	if @rc <> 0 goto ErrorHandler;

	set @i = @i + 1
end



exec dbo.prc_RaiseError 'Starting robocopy...', @@procid, @InfoOnly=1, @RunId=@RunId
exec dbo.prc_RaiseError '- Output file is %s', @@procid, 1, @TmpFileName, @InfoOnly=1, @RunId=@RunId

set @Cmd = 'ROBOCOPY "' + @SourceLogBackupFolderUNC + '" "' + @DesitnationLogBackupFolderName + '" "' + @SourceLogBackupFileNameTemplate + '" ' + @RobocopyOptions + ' ' + @AdditionalRobocopyOptions + ' > "' + @TmpFileName + '"'

set @rc = -1
set @tmpDate = getdate();

exec dbo.prc_RaiseError 'Issuing RoboCopy command: %s', @@procid, 1, @Cmd, @InfoOnly=1, @RunId=@RunId

delete from @CmdOutput
insert into @CmdOutput (CmdOutputLine)
exec @rc = master.dbo.xp_cmdshell @Cmd


-- load command output into a table so we can inspect it
set @Cmd2 = 'type "' + @TmpFileName + '"'
delete from @CmdOutput2
insert into @CmdOutput2 (CmdOutputLine)
exec master.dbo.xp_cmdshell @Cmd2
	
set @i = datediff(s, @tmpDate, getdate());
	
update  dbo.tblCustomLogShippingRuns
set RoboCopyDurationSeconds = @i
where RunId = @RunId


-- did we sucesfully invoke ROBOCOPY?
if not exists (select 1 from @CmdOutput2 where CmdOutputLine like '%Robust File Copy%')
begin
	exec dbo.prc_RaiseError 'ERROR: No robocopy output detected.', @@procid, @RunId=@RunId
	select * from @CmdOutput2
	select * from @CmdOutput
	set @rc = 1
	goto ErrorHandler
end
else if @rc = 0			-- Success - No copies necessary - already synchronised
	exec dbo.prc_RaiseError '- RoboCopy Success: RC %s: No copies necessary - already synchronised.', @@procid, 1, @rc, @InfoOnly=1, @RunId=@RunId
else if @rc = 1		-- Success - Copied one or more files
	exec dbo.prc_RaiseError '- RoboCopy Success: RC %s: Copied one or more files.', @@procid, 1, @rc, @InfoOnly=1, @RunId=@RunId
else if @rc = 2		-- Success - No copies necessary, some additional files exist in destination
	exec dbo.prc_RaiseError '- RoboCopy Success: RC %s: No copies necessary, some additional files exist in destination.', @@procid, 1, @rc, @InfoOnly=1, @RunId=@RunId
else if @rc = 3		-- Success - Copied one or more files, some additional files exist in destination
	exec dbo.prc_RaiseError '- RoboCopy Success: RC %s: Copied one or more files, some additional files exist in destination.', @@procid, 1, @rc, @InfoOnly=1, @RunId=@RunId
else
begin
	exec dbo.prc_RaiseError 'ERROR: Robocopy failed with RC %s. Robocopy command was: %s', @@procid, 2, @rc, @Cmd, @RunId=@RunId
	-- output the cmd output
	set @Cmd = 'type "' + @TmpFileName + '"'
	exec master.dbo.xp_cmdshell @Cmd 
	select * from @CmdOutput
	return 1
end

/*
Full list of robocopy return codes...

if errorlevel 16 echo ***FATAL ERROR*** & pause & goto end3
if errorlevel 15 echo ERROR 15. Copied some OK, but some copies FAILED or TIMED OUT & pause & goto end3
if errorlevel 14 echo ERROR 14. Some copies FAILED or TIMED OUT & pause & goto end3
if errorlevel 13 echo ERROR 13. Copied some OK, but some copies FAILED or TIMED OUT  & pause & goto end3
if errorlevel 12 echo ERROR 12. Some copies FAILED or TIMED OUT & pause & goto end3
if errorlevel 11 echo ERROR 11. Copied some OK, but some copies FAILED or TIMED OUT  & pause & goto end3
if errorlevel 10 echo ERROR 10. Some copies FAILED or TIMED OUT & pause & goto end3
if errorlevel 9 echo ERROR 9. Copied some OK, but some copies FAILED or TIMED OUT  & pause & goto end3
if errorlevel 8 echo ERROR 8. Some copies FAILED or TIMED OUT & pause & goto end3
if errorlevel 7 echo RC 7. Copied some OK, some MisMatches, some Extra & goto end3
if errorlevel 6 echo RC 6. Nothing Copied, some MisMatches, some Extra & goto end3
if errorlevel 5 echo RC 5. Copied some OK, some MisMatches & goto end3
if errorlevel 4 echo RC 4. Nothing Copied, some MisMatches & goto end3
if errorlevel 3 echo RC 3. Copied some OK, some Extras & goto end3
if errorlevel 2 echo RC 2. Nothing Copied, some Extras & goto end3
if errorlevel 1 echo RC 1. Success - Copied some files OK & goto end3
if errorlevel 0 echo RC 0. Success - No copies necessary, already in sync & goto end3
*/



--------------------------------------------------------------------
if isnull(@Credentials,'') <> ''
begin
	exec dbo.prc_RaiseError 'Issuing NET USE /DELETE for remote UNC: %s', @@procid, 1, @SourceLogBackupFolderUNC, @InfoOnly=1, @RunId=@RunId

	set @Cmd = 'net use "' + @SourceLogBackupFolderUNC + '" /delete /y '

	delete from @CmdOutput

	insert into @CmdOutput (CmdOutputLine)
	exec @rc = master.dbo.xp_cmdshell @Cmd
	
	if @rc <> 0
	begin
		exec dbo.prc_RaiseError 'NET USE /DELETE command failed with rc %s. Command was: %s', @@procid, 2, @rc, @Cmd, @InfoOnly=1, @RunId=@RunId
		select * from @CmdOutput
		set @rc = 1
		goto ErrorHandler
	end


end

--------------------------------------------------------------------
--
--  Load our list of source files into our table
--
exec dbo.prc_RaiseError 'Listing files in destination folder: %s matching: ', @@procid, 2, @DesitnationLogBackupFolderName, @SourceLogBackupFileNameTemplate, @InfoOnly=1, @RunId=@RunId

--
--  Because there can potentially be a lot of log files, for efficienvy, we use a small powershell script to list all files matching the wildcard and get fle size and file mod date
--
declare @PSTempFileName varchar(1000);
select @PSTempFileName = substring(physical_name,1,2) + '\tmpGetFileInfo_' + convert(varchar(100),@@spid) + '.ps1' from master.sys.database_files where name = 'master'

set @tmpDate = getdate();

-- build PS1 file
set @Cmd = 'del "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo $FolderName = $args[0] > "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo $SearchFileName = $args[1] >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo $Files = Get-ChildItem  -Path $FolderName -Filter $SearchFileName >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo if ($Files -eq $null) >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo { >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo 	write-host "ERROR: No files found in ''$FolderName'' matching ''$SearchFileName''." >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo } >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo else >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo { >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo     foreach ($File in $Files) >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo     { >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo         $FileName = $File.Name  >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo         $date = get-date $File.LastWriteTime -format ''yyyy-MM-dd HH:mm:ss.fff''  >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo         $Length = $File.Length  >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo         write-host "FileName: $FileName " >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo         write-host "FileDate: $date" >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo         write-host "FileLength: $Length" >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo     } >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output
set @Cmd = 'echo } >> "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output


Declare @tmp table (OutputLine NCHAR(1000), rownum INT IDENTITY(1,1));

-- execute the PS1 file
set @Cmd = 'powershell -file "' + @PSTempFileName + '" "' + @DesitnationLogBackupFolderName + '" "' + @SourceLogBackupFileNameTemplate + '"'
exec dbo.prc_RaiseError '  using command: %s', @@procid, 1, @Cmd, @InfoOnly=1, @RunId=@RunId

insert into @tmp (OutputLine)
exec @rc = master.dbo.xp_cmdshell @Cmd


if @rc <> 0 
begin
	exec dbo.prc_RaiseError 'ERROR: Bad RC from powershell when retrieving file size and date for files %s\%s.', @@procid, 1, @DesitnationLogBackupFolderName, @SourceLogBackupFileNameTemplate, @RunId=@RunId
	select * from @tmp
	return 1
end
if exists (select 1 from @tmp where OutputLine like '%Get-ChildItem : Cannot find path %')
begin
	exec dbo.prc_RaiseError 'ERROR: Folder does not exist: %s.', @@procid, 1, @DesitnationLogBackupFolderName, @RunId=@RunId
	select * from @tmp
	return 1
end
if exists (select 1 from @tmp where OutputLine like '%ERROR: No files found %')
begin
	exec dbo.prc_RaiseError 'ERROR: No log files found matching %s in %s.', @@procid, 2, @SourceLogBackupFileNameTemplate, @DesitnationLogBackupFolderName, @RunId=@RunId
	select * from @tmp
	return 1
end


declare OutputCsr cursor for
select OutputLine
from @tmp
where OutputLine like 'FileName: %'
   or OutputLine like 'FileDate: %'
   or OutputLine like 'FileLength: %'
order by rownum
set @rc = @@ERROR
if @rc <> 0 goto ErrorHandler

open OutputCsr
set @rc = @@ERROR
if @rc <> 0 goto ErrorHandler

set @AddedFilesCnt = 0;

while 1 = 1
begin
	fetch OutputCsr into @CmdOutputLine
	if @@fetch_status <> 0 break

	if @CmdOutputLine like 'FileName: %'
	begin
		set @ThisFileName = rtrim(ltrim(substring(@CmdOutputLine, len('FileName:') + 2, 99)))
		select @BackupFileDate  = null, @BackupFileSize = null

		-- next line is FileDate
		fetch OutputCsr into @CmdOutputLine
		if @@fetch_status <> 0 break

		if @CmdOutputLine like 'FileDate: %'
		begin
			select @CmdOutputLine = rtrim(ltrim(substring(@CmdOutputLine, len('FileDate:') + 2 ,30)))
			if isdate(@CmdOutputLine) = 1
				set @BackupFileDate = convert(datetime,@CmdOutputLine)

			-- next line is FileDate
			fetch OutputCsr into @CmdOutputLine
			if @@fetch_status <> 0 break

			if @CmdOutputLine like 'FileLength: %'
			begin
				select @CmdOutputLine = rtrim(ltrim(substring(@CmdOutputLine, len('FileLength:') + 2 ,30)))
				if isnumeric(@CmdOutputLine) = 1
					set @BackupFileSize = convert(bigint,@CmdOutputLine)
			end
		end


		If @BackupFileSize is null or @BackupFileDate is null
		begin
			exec dbo.prc_RaiseError 'ERROR: Cannot determine file size or last mod date for file %s.', @@procid, 1, @ThisFileName, @RunId=@RunId
			select * from @tmp
			select @BackupFileSize as 'FileSizeBytes', @BackupFileDate as 'FileModDate'
			close OutputCsr
			deallocate OutputCsr
			return 1
		end
		

		if not exists (select 1 from [dbo].[tblMigrationDatabaseLogBackups]
						where MigrationDatabaseName = @MigrationDatabaseName
						  and LogBackupFileName		= @ThisFileName)
		begin
			set @BackupFileSizeKB = @BackupFileSize / 1024
			exec dbo.prc_RaiseError '- Adding new file %s, size=%s KB, date=%s', @@procid, 3, @ThisFileName, @BackupFileSizeKB, @BackupFileDate, @InfoOnly=1, @RunId=@RunId

			insert into dbo.tblMigrationDatabaseLogBackups (MigrationDatabaseName, LogBackupFileName, LogBackupFolder, BackupFileSize, BackupFileDate, FoundByRunId, RestoredByRunId)
			values (@MigrationDatabaseName, @ThisFileName, @DesitnationLogBackupFolderName, @BackupFileSize, @BackupFileDate, @RunId, null)

			set @rc = @@error
			if @rc <> 0 Goto ErrorHandler

			set @AddedFilesCnt = @AddedFilesCnt + 1;

		end
--		else
--		begin
--			exec dbo.prc_RaiseError '  - Log backup file already known: %s', @@procid, 1, @ThisFileName, @InfoOnly=1, @RunId=@RunId
--		end
	end
end
close OutputCsr
deallocate OutputCsr

-- delete the PS1 file
set @Cmd = 'del "' + @PSTempFileName + '"'
exec master.dbo.xp_cmdshell @Cmd, no_output



set @i = datediff(s, @tmpDate, getdate());
	
update tblCustomLogShippingRuns
set FilesFound = @AddedFilesCnt,
	FindFilesDurationSeconds = @i
where RunId = @RunId

exec dbo.prc_RaiseError '%s new log backup files found.', @@procid, 1, @AddedFilesCnt, @InfoOnly=1, @RunId=@RunId

-----------------------------------------------------------------------
exec dbo.prc_RaiseError '%s exiting normally.', @@procid, 1, @ThisProc, @InfoOnly=1, @RunId=@RunId
return

-----------------------------------------------------------------------
ErrorHandler:
	if @rc = 1
		exec dbo.prc_RaiseError 'ERROR: Routine %s failed! See previous error message.', @@procid, 1, @ThisProc, @RunId=@RunId
	else
		exec dbo.prc_RaiseError 'ERROR: Routine %s failed! An unexected error has ocurred. Error code is %s.', @@procid, 2, @ThisProc, @rc, @RunId=@RunId
	return 1

go
-- ===========================================================================
if not exists (select * from sys.objects where name = 'prc_CheckLastFullDBRestore')
begin
	exec ('CREATE PROC dbo.prc_CheckLastFullDBRestore as print ''Dummy proc''; ');
end
go
alter PROCEDURE [dbo].[prc_CheckLastFullDBRestore]
(
 @MigrationDatabaseName		sysname,
 @RunId						int
)
as
set nocount on;
declare @Msg								varchar(1000);
declare @Cmd								varchar(1000);
declare @Cnt								int;
declare @rc									int;
declare @RestoredFilesCnt					int;
declare @FullDBBackupFinishDate				datetime;
declare @FullDBRestoreDate					datetime;
declare @BackupSetId						int;
declare @RestoreDate						datetime;
declare @BackupDate							datetime;
declare @DestinationDBName					sysname;
declare @tmp1								varchar(100);
declare @ThisProc							sysname;
set @ThisProc = object_name(@@procid);


exec dbo.prc_RaiseError ' ', @@procid, @InfoOnly=1, @RunId=@RunId
exec dbo.prc_RaiseError '%s started with migration DB name ''%s''.', @@procid, 2, @ThisProc,@MigrationDatabaseName, @InfoOnly=1, @RunId=@RunId


select	@DestinationDBName					= DestinationDBName,
		@FullDBBackupFinishDate				= FullDBBackupFinishDate,
		@FullDBRestoreDate					= FullDBRestoreDate
from dbo.tblMigrationDatabases
where MigrationDatabaseName = @MigrationDatabaseName

if @@rowcount = 0
begin;
	exec dbo.prc_RaiseError 'ERROR in proc %s: No record exists in table tblMigrationDatabases with MigrationDatabaseName=''%s''.', @@procid, 2, @ThisProc,@MigrationDatabaseName, @RunId=@RunId;
	return 1;
end;



--------------------------------------------------------------------
--
-- Check the DB exists and that it is "restoring"
--
if not exists (select * from sys.databases where name = @DestinationDBName)
begin;
	exec dbo.prc_RaiseError 'ERROR: Destination database ''%s'' does not exist.', @@procid, 1, @DestinationDBName, @RunId=@RunId;
	return 1;
end;
if not exists (select * from sys.databases where name = @DestinationDBName and state_desc = 'RESTORING')
begin;
	exec dbo.prc_RaiseError 'ERROR: Destination database ''%s'' does not have status ''RESTORING''.', @@procid, 1, @DestinationDBName, @RunId=@RunId;
	return 1;
end;

--------------------------------------------------------------------
--
--  Verify the most recent full DB restore so we can determine where log backup restores should start from 
--
exec dbo.prc_RaiseError 'Checking where TLog restores should start from...', @@procid, @InfoOnly=1, @RunId=@RunId

-- get the backup_set_id from the most recent FULL database restore for this database...
select	@BackupSetId = backup_set_id,
		@RestoreDate = restore_date
from msdb.dbo.restorehistory a
where destination_database_name = @DestinationDBName
	and restore_type = 'D'
	and restore_history_id = (select max(restore_history_id)
							from msdb.dbo.restorehistory b
							where a.destination_database_name = b.destination_database_name
								and a.restore_type = b.restore_type)
if @BackupSetId is null
begin	
	exec dbo.prc_RaiseError 'ERROR: Cannot find details of full DB restore of database ''%s'' in msdb.dbo.restorehistory.', @@procid, 1, @DestinationDBName, @RunId=@RunId
	set @rc = 1
	Goto ErrorHandler
end
	
set @tmp1 = convert(varchar(20), @RestoreDate, 120)
exec dbo.prc_RaiseError '- The most recent full restore for database ''%s'' was done at ''%s'', with backup_set_id ''%s''.', @@procid, 3, @DestinationDBName, @tmp1, @BackupSetId, @InfoOnly=1, @RunId=@RunId

select @BackupDate = backup_finish_date
from msdb.dbo.backupset 
where backup_set_id = @BackupSetId

if @BackupDate is null
begin	
	exec dbo.prc_RaiseError 'ERROR: Cannot find details of full DB backup msdb.dbo.backupset for backup_set_id %s.', @@procid, 1, @BackupSetId, @RunId=@RunId
	set @rc = 1
	Goto ErrorHandler
end

set @tmp1 = convert(varchar(20), @BackupDate, 120)
exec dbo.prc_RaiseError '- The most recent full DB restore for database ''%s'' was done using a backup that finished at ''%s''.', @@procid, 2, @DestinationDBName, @tmp1, @InfoOnly=1, @RunId=@RunId


if isnull(@RestoreDate,'2001-01-01') <> isnull(@FullDBRestoreDate,'2009-09-09')
begin;
	exec dbo.prc_RaiseError '- Database ''%s'': Either this is the first run for this database, or the database has undergone another restore since the previous run. Resetting all tlog backup records for this database.', @@procid, 1, @DestinationDBName, @InfoOnly=1, @RunId=@RunId

	update dbo.tblMigrationDatabaseLogBackups
	set RestoreStatus = 'Not Started', RestoredByRunId = null
	where MigrationDatabaseName = @MigrationDatabaseName

	update dbo.tblMigrationDatabases
	set	RestoredUpToDate = null
	where MigrationDatabaseName = @MigrationDatabaseName

end;
set @FullDBRestoreDate = @RestoreDate
set @FullDBBackupFinishDate = @BackupDate

-- record full backup finish date
update dbo.tblMigrationDatabases
set FullDBBackupFinishDate	= @FullDBBackupFinishDate,
	FullDBRestoreDate		= @FullDBRestoreDate
where MigrationDatabaseName = @MigrationDatabaseName



exec dbo.prc_RaiseError '%s exiting normally.', @@procid, 1, @ThisProc, @InfoOnly=1, @RunId=@RunId
return

-----------------------------------------------------------------------
ErrorHandler:
	if @rc = 1
		exec dbo.prc_RaiseError 'ERROR: Routine %s failed! See previous error message.', @@procid, 1, @ThisProc, @RunId=@RunId
	else
		exec dbo.prc_RaiseError 'ERROR: Routine %s failed! An unexected error has ocurred. Error code is %s.', @@procid, 2, @ThisProc, @rc, @RunId=@RunId
	return 1


go
-- ===========================================================================
if not exists (select * from sys.objects where name = 'prc_RestoreLogFiles')
begin
	exec ('CREATE PROC dbo.prc_RestoreLogFiles as print ''Dummy proc''; ');
end
go
alter PROCEDURE [dbo].[prc_RestoreLogFiles]
(
 @MigrationDatabaseName		sysname,
 @RunId						int
)
as
set nocount on;
declare @Msg								varchar(1000);
declare @Cmd								varchar(1000);
declare @Cnt								int;
declare @rc									int;
declare @RestoredFilesCnt					int;
declare @SourceDBServer						varchar(150);
declare @SourceDBName 						sysname;
declare @DestinationDBName	 				sysname;
declare @DesitnationLogBackupFolderName		varchar(500);
declare @BackupFileSize						bigint;
declare @BackupFileDate						datetime;
declare @RestoreUsingLiteSpeed				char(1);
declare @ThisFileName						varchar(1000);
declare @FullFileName						varchar(1000);
declare @tmp1								varchar(100);
declare @tmp2								varchar(100);
declare @tmpDate							datetime;
declare @i									int;
declare @FullDBBackupFinishDate				datetime;
declare @FullDBRestoreDate					datetime;
declare @CmdOutput table
(
	CmdOutputLine							varchar(1000) null,
	id										bigint identity primary key clustered
)
declare @ThisProc							sysname;
set @ThisProc = object_name(@@procid);


exec dbo.prc_RaiseError ' ', @@procid, @InfoOnly=1, @RunId=@RunId
exec dbo.prc_RaiseError '%s started with migration DB name ''%s''.', @@procid, 2, @ThisProc,@MigrationDatabaseName, @InfoOnly=1, @RunId=@RunId


select	@SourceDBServer						= SourceDBServer,
		@SourceDBName						= SourceDBName,
		@DestinationDBName					= isnull(DestinationDBName,SourceDBName),
		@DesitnationLogBackupFolderName		= DesitnationLogBackupFolderName,
		@RestoreUsingLiteSpeed				= RestoreUsingLiteSpeed,
		@FullDBBackupFinishDate				= FullDBBackupFinishDate,
		@FullDBRestoreDate					= FullDBRestoreDate
from dbo.tblMigrationDatabases
where MigrationDatabaseName = @MigrationDatabaseName

if @@rowcount = 0
begin
	exec dbo.prc_RaiseError 'ERROR in proc %s: No record exists in table tblMigrationDatabases with MigrationDatabaseName=''%s''.', @@procid, 2, @ThisProc,@MigrationDatabaseName, @RunId=@RunId
	return 1
end

if @RestoreUsingLiteSpeed = 'Y'
begin
	if not exists (select 1 from master.dbo.sysobjects where name = 'xp_restore_log')
	begin
		exec dbo.prc_RaiseError 'ERROR in proc %s: This tblMigrationDatabases record has @RestoreUsingLiteSpeed=''Y'', but SQL LiteSpeed routine ''xp_restore_log'' not found.', @@procid, 1, @ThisProc, @RunId=@RunId
		return 1
	end
end


set @DesitnationLogBackupFolderName = replace(@DesitnationLogBackupFolderName, '<server>', @SourceDBServer)
set @DesitnationLogBackupFolderName = replace(@DesitnationLogBackupFolderName, '<dbname>', @SourceDBName)


--------------------------------------------------------------------
--
-- if there are any log files that were produced before our FULL backup finished, mark them as not required
--
update dbo.tblMigrationDatabaseLogBackups
set RestoreStatus = 'Not Required', RestoredByRunId = @RunId
where MigrationDatabaseName = @MigrationDatabaseName
  and RestoreStatus in ('Not Started', 'Running', 'Failed')
  and BackupFileDate < @FullDBBackupFinishDate
select @rc = @@error, @Cnt = @@rowcount
if @rc <> 0 goto ErrorHandler

if @Cnt > 0
begin
	exec dbo.prc_RaiseError '- Marked %s log backup records as not required because they were produced before the full backup finished.', @@procid, 1, @Cnt, @InfoOnly=1, @RunId=@RunId
end

--------------------------------------------------------------------
--
--  Restore section: Now restore any files that have not yet been restored
--
set @tmpDate = getdate();

declare csrLogBackupFiles cursor for
select LogBackupFileName, LogBackupFolder, BackupFileSize, BackupFileDate
from dbo.tblMigrationDatabaseLogBackups
where MigrationDatabaseName = @MigrationDatabaseName
  and RestoreStatus in ('Not Started', 'Running', 'Failed')
order by BackupFileDate

set @rc = @@error 
if @rc <> 0 Goto ErrorHandler

open csrLogBackupFiles 
set @rc = @@error 
if @rc <> 0 Goto ErrorHandler

exec dbo.prc_RaiseError 'Starting log restores...', @@procid, @InfoOnly=1, @RunId=@RunId

set @RestoredFilesCnt = 0;
while 1 = 1
begin
	fetch csrLogBackupFiles into @ThisFileName, @DesitnationLogBackupFolderName, @BackupFileSize, @BackupFileDate
	if @@fetch_status <> 0 break

	set @FullFileName = @DesitnationLogBackupFolderName + '\' + @ThisFileName
	set @tmp1 = convert(varchar(20),@BackupFileDate,120)
	set @tmp2 = convert(varchar(20),@BackupFileSize / 1024) + ' KB'

	exec dbo.prc_RaiseError '- Restoring log backup file %s (date=%s, size=%s)...', @@procid, 3, @ThisFileName, @tmp1, @tmp2, @InfoOnly=1, @RunId=@RunId

	update dbo.tblMigrationDatabaseLogBackups
	set	RestoreStatus = 'Running',
		RestoreStart = getdate(),
		RestoredByRunId = @RunId
	where MigrationDatabaseName = @MigrationDatabaseName
	  and LogBackupFileName = @ThisFileName


	begin try;
		--
		--  Build the restore command
		--
		if @RestoreUsingLiteSpeed = 'Y'
		begin
			set @rc = 0
			exec @rc  = master.dbo.xp_restore_log @database = @DestinationDBName, @filename = @FullFileName, @with = 'norecovery'
			set @rc = isnull(@rc,0) + @@error
			if @rc <> 0
			begin
				exec dbo.prc_RaiseError 'ERROR: Bad RC (%s) during LiteSpeed log restore of %s', @@procid, 2, @rc, @FullFileName, @RunId=@RunId
				set @rc = 1
				close csrLogBackupFiles
				deallocate csrLogBackupFiles
				Goto ErrorHandler
			end
		end
		else
		begin
			set @rc = 0
			restore log @DestinationDBName from disk = @FullFileName with norecovery

			set @rc = isnull(@rc,0) + @@error
			if @rc <> 0
			begin
				exec dbo.prc_RaiseError 'ERROR: Bad RC (%s) during Native log restore of %s', @@procid, 2, @rc, @FullFileName, @RunId=@RunId
				set @rc = 1
				close csrLogBackupFiles
				deallocate csrLogBackupFiles
				Goto ErrorHandler
			end
		end;
	end try
	begin catch;
		set @Msg ='ERROR: Restore log backup for DB %s failed with error ' + isnull(convert(varchar(20),ERROR_NUMBER()),'<null>')
				+ ': ' + isnull(ERROR_MESSAGE(),'<null>')
				+ '. Log backup file was %s.'
		exec dbo.prc_RaiseError @Msg, @@procid, 2, @DestinationDBName, @ThisFileName, @RunId=@RunId
	
		exec dbo.prc_RaiseError 'NOTE: If this is the first log restore for this databsae, try makring this tblMigrationDatabaseLogBackups record as ''Not Required''.', @@procid, 0, @RunId=@RunId

		update dbo.tblMigrationDatabaseLogBackups
		set	RestoreStatus = 'Failed',
			RestoreFinish = getdate()
		where MigrationDatabaseName = @MigrationDatabaseName
		  and LogBackupFileName = @ThisFileName;
		
		close csrLogBackupFiles;
		deallocate csrLogBackupFiles;

		set @rc = 1;

		goto ErrorHandler;
	end catch;

	exec dbo.prc_RaiseError '- Restored log backup file OK: %s', @@procid, 1, @ThisFileName, @InfoOnly=1, @RunId=@RunId
	
	update dbo.tblMigrationDatabaseLogBackups
	set	RestoreStatus = 'Completed',
		RestoreFinish = getdate()
	where MigrationDatabaseName = @MigrationDatabaseName
	  and LogBackupFileName = @ThisFileName

	update dbo.tblMigrationDatabases
	set	RestoredUpToDate = @BackupFileDate
	where MigrationDatabaseName = @MigrationDatabaseName

	set @RestoredFilesCnt = @RestoredFilesCnt + 1

	update tblCustomLogShippingRuns
	set FilesRestored = @RestoredFilesCnt
	where RunId = @RunId
end
exec dbo.prc_RaiseError '%s log files restored OK.', @@procid, 1, @RestoredFilesCnt, @InfoOnly=1, @RunId=@RunId

close csrLogBackupFiles
deallocate csrLogBackupFiles

-----------------------------------------------------------------------
set @i = datediff(s, @tmpDate, getdate());

update tblCustomLogShippingRuns
set RunStatus = 'Success',
	RunEndTime = getdate(),
	RestoreDurationSeconds = @i
where RunId = @RunId

exec dbo.prc_RaiseError '%s exiting normally.', @@procid, 1, @ThisProc, @InfoOnly=1, @RunId=@RunId
return

-----------------------------------------------------------------------
ErrorHandler:
	if @rc = 1
		exec dbo.prc_RaiseError 'ERROR: Routine %s failed! See previous error message.', @@procid, 1, @ThisProc, @RunId=@RunId
	else
		exec dbo.prc_RaiseError 'ERROR: Routine %s failed! An unexected error has ocurred. Error code is %s.', @@procid, 2, @ThisProc, @rc, @RunId=@RunId
	return 1

go


-- ===========================================================================
if not exists (select * from sys.objects where name = 'prc_CustomLogShipping')
begin
	exec ('CREATE PROC dbo.prc_CustomLogShipping as print ''Dummy proc''; ');
end
go
alter PROCEDURE [dbo].[prc_CustomLogShipping]
(
 @MigrationDatabaseName		sysname,
 @StartFromStep				varchar(50) = null
)
as

set nocount on;
declare @Msg								varchar(1000);
declare @rc									int;
declare @DestinationDBName	 				sysname;
declare @RestoreUsingLiteSpeed				char(1);
declare @RunId								int;
declare @ThisProc							sysname;
set @ThisProc = object_name(@@procid);

insert into [dbo].[tblCustomLogShippingRuns] (RunStatus, [MigrationDatabaseName], [RunStartTime], [FilesFound], [FilesRestored], [RunUserid], [RunProgram], [RunSIPD], [RunClientHost])
select 'Running', @MigrationDatabaseName, getdate(), 0, 0, ltrim(rtrim(suser_sname())), ltrim(rtrim(program_name())), @@spid, ltrim(rtrim(host_name()))
select @RunId = SCOPE_IDENTITY()




exec dbo.prc_RaiseError '%s started with migration DB name ''%s''.', @@procid, 2, @ThisProc,@MigrationDatabaseName, @InfoOnly=1, @RunId=@RunId
exec dbo.prc_RaiseError 'This is RunId %s.', @@procid, 1, @RunId, @InfoOnly=1, @RunId=@RunId

update [tblCustomLogShippingRuns]
set RunStatus = 'Failed by Next Run'
where MigrationDatabaseName = @MigrationDatabaseName
  and RunStatus = 'Running'
  and RunId < @RunId
set @rc = @@rowcount
if @rc > 0
	exec dbo.prc_RaiseError '%s previous tblCustomLogShippingRuns records for this database have been marked as ''Failed by Next Run''.', @@procid, 1, @rc, @InfoOnly=1, @RunId=@RunId



select	@DestinationDBName					= isnull(DestinationDBName,SourceDBName),
		@RestoreUsingLiteSpeed				= RestoreUsingLiteSpeed
from dbo.tblMigrationDatabases
where MigrationDatabaseName = @MigrationDatabaseName

if @@rowcount = 0
begin
	exec dbo.prc_RaiseError 'ERROR in proc %s: No record exists in table tblMigrationDatabases with MigrationDatabaseName=''%s''.', @@procid, 2, @ThisProc,@MigrationDatabaseName, @RunId=@RunId
	goto ErrorHandler
end

if @RestoreUsingLiteSpeed = 'Y'
begin
	if not exists (select 1 from master.dbo.sysobjects where name = 'xp_restore_log')
	begin
		exec dbo.prc_RaiseError 'ERROR in proc %s: This tblMigrationDatabases record has @RestoreUsingLiteSpeed=''Y'', but SQL LiteSpeed routine ''xp_restore_log'' not found.', @@procid, 1, @ThisProc, @RunId=@RunId
		set @rc = 1
		goto ErrorHandler
	end
end



if isnull(@StartFromStep,'') = ''
	-- do nothing
	set @StartFromStep = @StartFromStep
else if upper(@StartFromStep) = upper('RestoreLogs')
begin
	exec dbo.prc_RaiseError 'Starting this run from step: %s.', @@procid, 1, @StartFromStep, @InfoOnly=1, @RunId=@RunId
	goto RestoreLogs
end
else 
begin
	exec dbo.prc_RaiseError 'ERROR in proc %s: Unknown @StartFromStep value of ''%s''. Valid values are blank or ''RestoreLogs''.', @@procid, 2, @ThisProc, @StartFromStep, @RunId=@RunId
	set @rc = 1
	goto ErrorHandler
end

--------------------------------------------------------------------
--
--  Verify which Full Backup was last restored for this database
--
exec @rc = dbo.prc_CheckLastFullDBRestore @MigrationDatabaseName, @RunId=@RunId
if @rc <> 0 goto ErrorHandler

--------------------------------------------------------------------
--
--  First, call the routine to copy the latest TLog files here...
--
exec @rc = dbo.prc_CopyLogFiles @MigrationDatabaseName, @RunId=@RunId
if @rc <> 0 goto ErrorHandler


--------------------------------------------------------------------
--
--  Now call the routine to perform log restores
--
RestoreLogs:
exec @rc = dbo.prc_RestoreLogFiles @MigrationDatabaseName, @RunId=@RunId
if @rc <> 0 goto ErrorHandler

-----------------------------------------------------------------------
exec dbo.prc_RaiseError '%s exiting normally.', @@procid, 1, @ThisProc, @InfoOnly=1, @RunId=@RunId
return

-----------------------------------------------------------------------
ErrorHandler:
	update tblCustomLogShippingRuns
	set RunStatus = 'Failed',
		RunEndTime = getdate()
	where RunId = @RunId

	if @rc = 1
		exec dbo.prc_RaiseError 'ERROR: Routine %s failed! See previous error message.', @@procid, 1, @ThisProc, @RunId=@RunId
	else
		exec dbo.prc_RaiseError 'ERROR: Routine %s failed! An unexected error has ocurred. Error code is %s.', @@procid, 2, @ThisProc, @rc, @RunId=@RunId
	return 1


go
if object_id('dbo.prc_CycleFiles') is null
	exec ('create proc dbo.prc_CycleFiles as select 1;');
go
alter procedure dbo.prc_CycleFiles 
(
 @Path				varchar(500), 
 @FileName			varchar(100),
 @NumberOfCopies	int		= 10,	-- how many copies should be retained
 @Debug 			char(1)	= 'N'
)
as
--
-- =============================================================================
--
--  Purpose: 	Cycles files down by renaming with _1, _2, _3 notation.
--
--  We keep 'n' old copies of the olap backup file
--		delete FileName_'n'.txt
--		rename FileName_'n-1'.txt FileName_'n'.txt
--		rename FileName_'n-2'.txt FileName_'n-1'.txt
--		rename ....					....
--		rename FileName_1.txt FileName_2.txt
--		rename FileName.txt   FileName_1.txt
--
-- Maintenance Log:
--  When	Who	Ver	What
--  ==========	===	===	==============================
--  18/10/2006	gab	1.0	Created Original
--
-- =============================================================================
--  
set nocount on

declare @FileSuffix varchar(50), @FileNameWithoutSuffix varchar(100), @tmp varchar(100), @i int
declare @FileNum int, @Cmd varchar(1000), @ThisFile varchar(100)
declare @ThisProc sysname, @rc int, @exists int, @Msg nvarchar(1000);

select @ThisProc = object_name(@@procid)

--  wildcards are not allowed in the file name
if @FileName like '%[*]%'
or @FileName like '%[_]%'
or @FileName like '%[?]%'
begin
	set @Msg = 'ERROR in ' + @ThisProc + ': This routine cannot process file names that include wildcard characters.'
	raiserror (@Msg, 16,16);
	return 1
end


if right(@Path,1) <> '\'
	select @Path = @Path + '\'
if upper(@Path) like 'C:\WIN%'
or upper(@Path) like upper('C:\Program Files%')
begin
	set @Msg = 'ERROR in ' + @ThisProc + ': This routine cannot cycle files in windows or program files folders.'
	raiserror (@Msg, 16,16);
	return 1
end
--  first, get file suffix
select @tmp = reverse(@FileName)
select @i = charindex('.', @tmp)
if @i = 0
	select	@FileSuffix = '',
			@FileNameWithoutSuffix = @FileName
else
	select	@FileSuffix = reverse(substring(@tmp, 1, @i)),
			@FileNameWithoutSuffix = substring(@FileName, 1, len(@FileName) - @i)

if upper(@FileSuffix) in ('.EXE', '.DLL', '.RLL', '.OCX', '.REG', '.SCR', '.SYS', '.VXD')
begin
	set @Msg = 'ERROR in ' + @ThisProc + ': This routine cannot cycle files with the specified suffix (' + @FileSuffix + ').'
	raiserror (@Msg, 16,16);
	return 1
end

select @tmp = @Path + @FileName
exec master.dbo.[xp_fileexist] @tmp, @rc out

if @rc = 1
begin
	-----------------------------------------------------------------------------------------------
	--
	--  OK, the file exists so we need to do the rename and here we go
	--
	Print 'Rolling files down: ' + @tmp

	select @FileNum = @NumberOfCopies
	while @FileNum >= 0
	begin
		if @FileNum = 0
			select @ThisFile = @FileName
		else
			select @ThisFile = @FileNameWithoutSuffix + '_' + convert(varchar(10),@FileNum) + @FileSuffix

		if @FileNum = @NumberOfCopies
		begin
			select @Cmd = 'del "' + @Path + @ThisFile + '"'
			print @Cmd
			exec master..[xp_cmdshell] @Cmd, no_output
		end
		else
		begin
			select @Cmd = 'ren "' + @Path + @ThisFile + '" "' + @FileNameWithoutSuffix + '_' + convert(varchar(10),@FileNum + 1) + @FileSuffix + '"'
			print @Cmd
			exec master..[xp_cmdshell] @Cmd, no_output
		end
		select @FileNum = @FileNum - 1
	end
end
else
	Print 'File does not exist: ' + @tmp
print 'Done.'
GO

use master
go

