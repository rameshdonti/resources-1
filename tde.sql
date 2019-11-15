

/******************************************************************************/


USE [master];
GO
-- ==============================================================================
--  Create the TDEAdmin database if it doesnt already exist...

if db_id('TDEAdmin') is not null
	print convert(varchar(30),getdate(),120) + ' [Info] TDEAdmin database already exists OK.';
else
begin;
	print convert(varchar(30),getdate(),120) + ' [Info] Creating database TDEAdmin...';
	exec ('CREATE DATABASE [TDEAdmin];');

	exec ('ALTER AUTHORIZATION ON DATABASE::TDEAdmin TO [sa];');

end;

go
if exists (select 1 from sys.databases where name = 'TDEAdmin' and recovery_model_desc <> 'SIMPLE')
begin;
	print convert(varchar(30),getdate(),120) + ' [Info] Setting TDEAdmin to SIMPLE recovery mode...';
	exec ('ALTER DATABASE [TDEAdmin] SET RECOVERY SIMPLE;');
end;
go


USE [TDEAdmin];
go
print convert(varchar(30),getdate(),120) + ' [Info] Creating tables...';
go
if db_name() <> 'TDEAdmin'
	return;

-- drop table TDEAdmin..tblTDEData
if object_id('dbo.tblTDEData') is null
	create table dbo.tblTDEData
	(id int			identity,
	 RecordType		varchar(20) not null check (RecordType in ('Data', 'Version')),
	 CreateDate		datetime null,
	 CreateUser		sysname null,
	 CreateProgram	sysname null,
	 LastModDate	datetime null,
	 LastModUser	sysname null,
	 LastModProgram	sysname null,
	 Value			sql_variant null,
	primary key clustered 
		(
			id ASC
		)
	);

if not exists (select 1 from sys.indexes where object_id = object_id('tblTDEData') and name = 'IX_tblTDEData_Date')
	create unique nonclustered index IX_tblTDEData_Date on dbo.tblTDEData (CreateDate, id);

-- drop table tblMessageLog
if OBJECT_ID('dbo.tblMessageLog') is null
	CREATE TABLE dbo.tblMessageLog(
		MessageId		int identity(1,1) not for replication not NULL,
		MessageTime		datetime not NULL default (getdate()),
		MessageType		varchar (10) not NULL,
		MessageText		varchar (max) not NULL,
		ProcName		sysname NULL,
		LoggingSPID		int null default (@@spid),
		LoggingUserid	sysname null default (system_user),
		LoggingProgram	sysname null default (program_name()),
		LoggingHostName	sysname null default (host_name()),
	primary key clustered 
		(
			MessageId ASC
		)
	);

if not exists (select 1 from sys.indexes where object_id = object_id('tblMessageLog') and name = 'IX_tblMessageLog_Time')
	create unique nonclustered index IX_tblMessageLog_Time on dbo.tblMessageLog (MessageTime, MessageId);
go
if object_id('trg_TDEData_UI') is not null
	drop trigger trg_TDEData_UI;
go
create trigger trg_TDEData_UI
on tblTDEData
for insert, update
as
set nocount on;

-- exit without doing anything if nothing was changed
if  not exists (select 1 from inserted)
and not exists (select 1 from deleted)
	return;

-- for insert statements, set the Create values back to originals (prevent people from changing history)
if (select count(*) from deleted) = 0
	update t
	set CreateDate = getdate(),
		CreateUser = system_user,
		CreateProgram = program_name(),
		LastModDate = getdate(),
		LastModUser = system_user,
		LastModProgram = program_name()
	from inserted i
	join dbo.tblTDEData t
		on t.id = i.id;

-- for update statements, set the Create values back to originals (prevent people from changing history)
else
	update t
	set CreateDate = d.CreateDate,
		CreateUser = d.CreateUser,
		CreateProgram = d.CreateProgram
	from inserted i
	join deleted d
		on i.id = d.id
	join dbo.tblTDEData t
		on t.id = i.id;
go

-- Save the script version if it is not already set correctly...
set nocount on;
declare @ScriptVersion varchar(10) = '2.04';
if not exists (select 1 from dbo.tblTDEData where RecordType = 'Version')
	insert into dbo.tblTDEData (RecordType, Value)
	values('Version', @ScriptVersion);
else if exists (select 1 from dbo.tblTDEData where RecordType = 'Version' and isnull(Value,'?') <> @ScriptVersion)
	update dbo.tblTDEData 
	set Value = @ScriptVersion
	where RecordType = 'Version';
go


print convert(varchar(30),getdate(),120) + ' [Info] Creating/Altering stored procedures...';
go
-- ==============================================================================
--  drop old stored procedures from v1.2 of the scripts that are no longer used...
if object_id('[dbo].[PRA_GENERATE_PASSWORDS_TDE]') is not null
begin;
	drop procedure [dbo].[PRA_GENERATE_PASSWORDS_TDE];
end;
if object_id('[dbo].[PRA_RESTORE_TDE]') is not null
begin;
	drop procedure [dbo].PRA_RESTORE_TDE;
end;
if object_id('[dbo].[PRA_Restore_OTHRENV_TDE_DB]') is not null
begin;
	drop procedure [dbo].PRA_Restore_OTHRENV_TDE_DB;
end;
if object_id('[dbo].[PRA_GET_PASSWORDS_TDE]') is not null
begin;
	drop procedure [dbo].PRA_GET_PASSWORDS_TDE;
end;
if object_id('[dbo].[PRA_GENERATE_TDE_RESTORE_SCRIPT]') is not null
begin;
	drop procedure [dbo].PRA_GENERATE_TDE_RESTORE_SCRIPT;
end;
if object_id('[dbo].[PRA_DEPLOY_TDE]') is not null
begin;
	drop procedure [dbo].PRA_DEPLOY_TDE;
end;
if object_id('[dbo].[PRA_CHECK_TDE]') is not null
begin;
	drop procedure [dbo].PRA_CHECK_TDE;
end;
if object_id('[dbo].[PRA_TDE_TURNOFF]') is not null
begin;
	drop procedure [dbo].PRA_TDE_TURNOFF;
end;
if object_id('[dbo].[PRA_TDE_KEYS_BACKUP]') is not null
begin;
	drop procedure [dbo].PRA_TDE_KEYS_BACKUP;
end;
if object_id('[dbo].[PRA_GENERATE_TDE_SCRIPT]') is not null
begin;
	drop procedure [dbo].PRA_GENERATE_TDE_SCRIPT;
end;


go
-- ======================================================================================================================
if object_id('prcLogMessage') is null
	exec ('CREATE PROCEDURE [prcLogMessage] as select 1');

GO
alter PROCEDURE [prcLogMessage]
(
	@MessageText	[varchar] (max),
	@MessageType	[varchar] (10) = 'Info',
	@ProcName		[sysname] = null
)		
AS
/************************************************************************************************
	Routine to insert a single message record into tblMessageLog

	Maintenance Log:
	When		Who					What
	----------	-------------------	----------------------------------------------------------------------
	26/03/2014	Geoff Baxter		Created original
	23/10/2014	Geoff Baxter		Copied from Generic Data Purge routines and amended

************************************************************************************************/
set nocount on;
Declare @d datetime;
Declare @Indent int;

if @MessageText is null set @MessageText = '<null>';
if @MessageText  = '<LogProcStartMsg>'  set @MessageText = isnull(@ProcName,'<UnknownProc>') + ' has started.';
if @MessageText  = '<LogProcEndMsg>'    set @MessageText = isnull(@ProcName,'<UnknownProc>') + ' has ended OK.';

set @Indent = (@@NESTLEVEL - 2) * 2;
if @Indent < 0 set @Indent = 0;
set @MessageText = replicate(' ', @Indent) + @MessageText;

set @d = getdate();

if @MessageType is null set @MessageType = 'Info';

if @MessageText <> ''	-- no point logging blank messages
	insert into [tblMessageLog] ([MessageTime], [MessageType], [MessageText], 	[ProcName], [LoggingSPID], [LoggingUserid], [LoggingProgram], [LoggingHostName])
	values (@d, @MessageType, @MessageText, @ProcName, @@spid, SUSER_SNAME(), program_name(), host_name());

print convert(varchar(30),@d,120) + ' [' + @MessageType + '] ' + @MessageText;

set @MessageText = ltrim(rtrim(@MessageText));
set @MessageText = replace(@MessageText,'%','%%');
if upper(@MessageType) = upper('ERROR')
	Raiserror (@MessageText, 16,16);

go
Declare @ScriptName		sysname = 'TDE Config Script';
exec dbo.prcLogMessage 'TDE Configuration script is now logging messages to tblMessageLog.', @ProcName=@ScriptName;
exec dbo.prcLogMessage 'TDE Configuration script: Creating/Altering stored procedures...', @ProcName=@ScriptName;
go
-- ======================================================================================================================
if not exists (select * from dbo.sysobjects where id = object_id(N'[dbo].[fnGetEncryptionStateDescription]') )
	exec ('create function dbo.fnGetEncryptionStateDescription () returns int as begin return 1 end');
GO
set QUOTED_IDENTIFIER ON;
set ANSI_NULLS ON;
GO

ALTER function dbo.fnGetEncryptionStateDescription (@State int)
returns varchar(200)
as
/************************************************************************************************
	

************************************************************************************************/
begin;

	declare @Result varchar(200) = 
		case isnull(@State,0)
			when 0 then 'No database encryption key present, no encryption'
			when 1 then 'Unencrypted'
			when 2 then 'Encryption in progress'
			when 3 then 'Encrypted'
			when 4 then 'Key change in progress'
			when 5 then 'Decryption in progress'
			when 6 then 'Protection change in progress (The certificate or asymmetric key that is encrypting the database encryption key is being changed).'
			else 'Unknown state' 
		end + ' [' + isnull(convert(varchar(10),isnull(@State,0)),'<null>') + ']';

	return @Result;
end;
go

-- ======================================================================================================================
if not exists (select * from dbo.sysobjects where id = object_id(N'[dbo].[prcGetRandomInteger]') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
	exec ('create procedure [dbo].[prcGetRandomInteger] as print ''Dummy proc'';');
GO
set QUOTED_IDENTIFIER ON ;
set ANSI_NULLS ON ;
GO

ALTER procedure dbo.[prcGetRandomInteger]
(@RandomNumber 	int = 0 out,
 @MinValue 	int = 0,
 @MaxValue	int = 100,
 @print		char(1) = 'N',
 @Debug		char(1) = 'N'
)
as
/************************************************************************************************

  Procedure to generate a random integer value in the specified range.

 Log:
  When		Who				Ver	What
 ==========	===============	===	=====================================================================================
 01/05/2002	Geoff Baxter	1.0	Created original
 20/12/2004	Surajit		1.1 Checked the database variables data type to sysname referring to SQL Server object.
								Enclosed all the SQL Server objects in the stored procedures within square brackets.
 23/10/2014	Geoff Baxter	1.2	Copied from old DBAdmin source to be part of TDEAdmin routines.
 06/11/2014	Geoff Baxter	1.3	Altered algorythm somewhat to improve randomness for the highest & lowest values.
************************************************************************************************/

Declare @Rnd				float;
Declare @seed				int;
Declare @ProcName			sysname			= object_name(@@procid);
Declare @NumValues			float;

select @RandomNumber = 0;
if @MinValue is null select @MinValue = 0;
if @MaxValue is null select @MaxValue = 100;
if @MinValue >= @MaxValue
begin;
	exec dbo.prcLogMessage '@MinValue must be less than @MaxValue in [prcGetRandomInteger].', 'Error', @ProcName=@ProcName;
	return 1;
end;
set @NumValues = @MaxValue - @MinValue + 1;
if @Debug = 'Y' print 'numvalues = ' + convert(varchar(10),@NumValues);
--
--  Generate a random float number between 0 and 1
--
select @Rnd = rand();
if @Debug = 'Y' print 'rand() = ' + ltrim(str(@Rnd,10,5));

--
--  Convert it into the range we need
--  With the default Min & Max values of 0 and 100, we should now have
--  a random number between 0 and 100 (101 values).
select @Rnd  = @Rnd * @NumValues;
if @Debug = 'Y' print 'next = ' + ltrim(str(@Rnd,10,5)) + ', multiplier = ' + convert(varchar(10), @NumValues);

--
-- This gives us a number in the required range (e.g., with default values, then 0.00001..99.99999)
-- However to get the first and last values ocurring with equal probabbility to all others we need to subtract 0.5 before rounding
-- i.e. make it -0.49999 - 99.4999999)
set @Rnd = @Rnd - 0.5;
if @Debug = 'Y' print 'scaled = ' + ltrim(str(@Rnd,10,5));

--
--  Convert it to an integer, with rounding
--
select @RandomNumber = convert(int,round(@Rnd, 0));
if @Debug = 'Y' print 'Random = ' + convert(varchar(10),@RandomNumber);
--
--  And apply our minimum value
--
select @RandomNumber = @MinValue + @RandomNumber;
--
--  Finally, ensure the number is in the correct range.
--
if @RandomNumber < @MinValue
begin;
	if @Debug = 'Y' print 'Forcing min = ' + convert(varchar(10),@RandomNumber);
	select @RandomNumber = @MinValue;
end;
if @RandomNumber > @MaxValue
begin;
	if @Debug = 'Y' print 'Forcing max = ' + convert(varchar(10),@RandomNumber);
	select @RandomNumber = @MaxValue;
end;
--
-- All done.
--
if @Debug = 'Y' or @print = 'Y'
	print 'Generated Number = ' + convert(varchar(10),@RandomNumber);

GO

set QUOTED_IDENTIFIER ON ;
set ANSI_NULLS ON ;
GO

-- ======================================================================================================================

if not exists (select * from dbo.sysobjects where id = object_id(N'[dbo].[prcGetRandomString]') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
	exec ('create procedure [dbo].[prcGetRandomString] as print ''Dummy proc.'' ');
GO

ALTER procedure dbo.[prcGetRandomString]
(@RandomString 					varchar(1000) = '' out,
 @RandomStringPhonetic			varchar(max) = '' out,
 @MinLength						int = 10,
 @MaxLength						int = 10,
 @AllowNumbers					char(1) = 'Y',
 @AllowSpecialcharacters		char(1) = 'Y',
 @ForceAtLeastOneNumber			char(1) = 'Y',
 @ForceAtLeastOneSpecialchar	char(1) = 'Y',
 @AllowSpaces					char(1) = 'N',
 @print							char(1) = 'N',
 @Debug							char(1) = 'N',
 @Debug2						char(1) = 'N'
)
as
/************************************************************************************************
  Procedure to generate a random string of a specified length.

  The first character is always a letter (never a number, space or special char)

 Log:
  When		Who				Ver	What
  =========	=============	===	=====================================================================================
 01/05/2002   Geoff Baxter	1.0	Created original
 20/12/2004   Surajit		1.1 Checked the database variables data type to sysname referring to SQL Server object.
								Enclosed all the SQL Server objects in the stored procedures within square brackets.
 13/07/2006   GeoffB		1.2 Added @ForceAtLeastOneNumber and @ForceAtLeastOneSpecialchar options for SQL 2005.
								Now, by default we have the following rules:
									- First character will be A..Z or a..z
									- Must contain at least one number
									- Must contain at least one special character
 20/10/2014   Geoff Baxter	1.3	Copied from old DBAdmin source to be part of TDEAdmin routines.
									- Enhanced to distinguish between upper case and lower case strings
 06/11/2014   Geoff Baxter	1.4	When forcing a number or a special character, now put it into a random position rather than a hard-coded position.
									- Also include logic to prevent clashes when forcing both a number and a special character.

************************************************************************************************/
set nocount on;
  
Declare @charsOnly			varchar(100);
Declare @Thischar			int;
Declare @j					int;
Declare	@rc					int;
Declare @MinValue			int;
Declare @MaxValue			int;
Declare @RandomNumber		int;
Declare @ReplacingcharacterId int;
Declare @ForcedNumberPosition int;
Declare @ClashCount			int;
Declare @StringLength		int;
Declare @Onechar			varchar(1);
Declare @strMsg				varchar(1000);
Declare @FinalLetterPosition  int;
Declare @ProcName			sysname			= object_name(@@procid);
select @RandomString = '';
select @RandomStringPhonetic = '';
 
-- 
--  if we need to force at least 1 number or special char, then obviously these must be allowed.
if @ForceAtLeastOneNumber		= 'Y' set @AllowNumbers		= 'Y';
if @ForceAtLeastOneSpecialchar	= 'Y' set @AllowSpecialcharacters	= 'Y';


--  Initialise a table containing all the possible characters...

Declare @characters table 
(
	id				int identity primary key, 
	charType		varchar(10), 
	charValue		char(1), 
	charName		varchar(20)
);
Declare @RandomStringTable table 
(
	id				int identity primary key, 
	charType		varchar(10), 
	charValue		char(1), 
	charName varchar(20)
);

insert into @characters (charType, charValue, charName)
values	('Upper', 'A', 'Alpha'),
		('Upper', 'B', 'Bravo'),
		('Upper', 'C', 'charlie'),
		('Upper', 'D', 'Delta'),
		('Upper', 'E', 'Echo'),
		('Upper', 'F', 'Foxtrot'),
		('Upper', 'G', 'Golf'),
		('Upper', 'H', 'Hotel'),
		('Upper', 'I', 'India'),
		('Upper', 'J', 'Juliett'),
		('Upper', 'K', 'Kilo'),
		('Upper', 'L', 'Lima'),
		('Upper', 'M', 'Mike'),
		('Upper', 'N', 'November'),
		('Upper', 'O', 'Oscar'),
		('Upper', 'P', 'Papa'),
		('Upper', 'Q', 'Quebec'),
		('Upper', 'R', 'Romeo'),
		('Upper', 'S', 'Sierra'),
		('Upper', 'T', 'Tango'),
		('Upper', 'U', 'Uniform'),
		('Upper', 'V', 'Victor'),
		('Upper', 'W', 'Whiskey'),
		('Upper', 'X', 'X-ray'),
		('Upper', 'Y', 'Yankee'),
		('Upper', 'Z', 'Zulu');

-- Ensure they are all upper case...
update @characters
set charValue = upper(charValue),
	charName  = upper(charName);

-- Now insert the lower case characters...
insert into @characters (charType, charValue, charName)
select 'Lower', lower(charValue), lower(charName)
from @characters;

select @FinalLetterPosition  = max(id) from @characters;

if @AllowNumbers = 'Y'
	insert into @characters (charType, charValue, charName)
	values	('Number', '0', 'Zero'),
			('Number', '1', 'One'),
			('Number', '2', 'Two'),
			('Number', '3', 'Three'),
			('Number', '4', 'Four'),
			('Number', '5', 'Five'),
			('Number', '6', 'Six'),
			('Number', '7', 'Seven'),
			('Number', '8', 'Eight'),
			('Number', '9', 'Nine');


if @AllowSpecialcharacters = 'Y'
	insert into @characters (charType, charValue, charName)
	values	('Special', '!', 'Exclamation'),
			('Special', '@', 'At-Sign'),
			('Special', '#', 'Hash'),
			('Special', '$', 'Dollar'),
			('Special', '%', 'Percent'),
			('Special', '^', 'Circumflex'),
			('Special', '&', 'Ampersand'),
			('Special', '*', 'Asterisk'),
			('Special', '_', 'Underscore'),
			('Special', '-', 'Dash'),
			('Special', '=', 'Equals'),
			('Special', '+', 'Plus');

if @AllowSpaces = 'Y'
	insert into @characters (charType, charValue, charName)
	values	('Special', ' ', 'Space');


--
--  First, work out exactly how long this random string will be
--  if the MinLength = MaxLength, then we use this length
--  Otherwise we use a random length between MinLength & MaxLength
--
if @MinLength = @MaxLength
	select @StringLength = @MinLength;
else
begin;
	exec dbo.[prcGetRandomInteger] @StringLength OUT, @MinValue=@MinLength, @MaxValue=@MaxLength, @print='N', @Debug=@Debug2;
	if not @StringLength between @MinLength and @MaxLength
	begin;
		set @strMsg = 'ERROR: Invalid random number generated. ' + convert(varchar(10),isnull(@StringLength,'')) + 
					' should be between ' + convert(varchar(10),isnull(@MinLength,'')) + 
					' and ' + convert(varchar(10),isnull(@MaxLength,'')) + ' (' + @ProcName + ').';
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
	end;
end;
if @Debug='Y'
	print 'Will generate a string of ' + convert(varchar(10),isnull(@StringLength,'')) + ' chars.';

--  if we want a 0 length string, then we are done
if @StringLength < 1
	goto EndOfProc;


-- =========================================================================
--
--  Now Get our first character (which is always a letter)
--
exec dbo.[prcGetRandomInteger] @RandomNumber OUT, @MinValue=1, @MaxValue=@FinalLetterPosition, @print='N', @Debug=@Debug2;
if not @RandomNumber between 1 and @FinalLetterPosition 
begin;
	set @strMsg = 'ERROR: Invalid random number generated. ' + convert(varchar(10),isnull(@RandomNumber,'')) + 
					' should be between 1 and ' + convert(varchar(10),isnull(@FinalLetterPosition,'')) + 
					' (' + @ProcName + ').';
	exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
	return 1;
end;

-- And extract the character that matches this random number.
insert into @RandomStringTable (charType, charValue, charName)
select charType, charValue, charName
from @characters
where id = @RandomNumber;

if @@rowcount = 0
begin;
	set @strMsg = 'ERROR: Internal error in ' + @ProcName + ': No character found with id matching randomly generated number ' + convert(varchar(10),isnull(@RandomNumber,'')) + '.';
	exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
	return 1;
end;

-- =========================================================================
--
--  Now we have the 1st character, generate the remainder.
--
--  Any remaining characters can have additional chars depending on the parameters passed.
--  Add any extra chars into the array of possible characters.
--

select @MaxValue = max(id)
from @characters;

--
--  Generate the remaining characters (if any)
--
select @Thischar = 1;
while @Thischar < @StringLength
begin;
	--  get the next character
	select @Thischar = @Thischar + 1;

	--  Get a random number pointing to the next character
	exec dbo.[prcGetRandomInteger] @RandomNumber OUT, @MinValue=1, @MaxValue=@MaxValue, @print='N', @Debug=@Debug2;
	if not @RandomNumber between 1 and @MaxValue
	begin;
		set @strMsg = 'ERROR: Invalid random number generated. ' + convert(varchar(10),isnull(@RandomNumber,'')) + 
					' should be between 1 and ' + convert(varchar(10),isnull(@MaxValue,'')) + 
					' (' + @ProcName + ').';
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
	end;

	-- And extract the character that matches this random number.
	insert into @RandomStringTable (charType, charValue, charName)
	select charType, charValue, charName
	from @characters
	where id = @RandomNumber;

	if @@rowcount = 0
	begin;
		set @strMsg = 'ERROR: Internal error in ' + @ProcName + ': No character found with id matching randomly generated number ' + convert(varchar(10),isnull(@RandomNumber,'')) + ' when getting character #' + convert(varchar(10),isnull(@Thischar,'')) + '.';
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
	end;
end;

-- =========================================================================
-- OK, we have our string.  
-- If we were asked to ensure there is at least one number in it, check this now...
--
--  now if we need to force at least one number, then do so if we havent already got a number
set @ForcedNumberPosition = 0;
if @ForceAtLeastOneNumber = 'Y' and @StringLength >= 3 and not exists (select 1 from @RandomStringTable where charType = 'Number')
begin;
	--
	-- We need to replace one of the characters with a number
	-- Which character should we replace? Get a random number in the range of 2 to password length (we never replace the first character)
	--
	exec dbo.[prcGetRandomInteger] @RandomNumber OUT, @MinValue=2, @MaxValue=@StringLength, @print='N', @Debug=@Debug2;
	if not @RandomNumber between 2 and @StringLength
	begin;
		set @strMsg = 'ERROR: Invalid random number generated. ' + convert(varchar(10),isnull(@RandomNumber,'')) + 
					' should be between 2 and ' + convert(varchar(10),isnull(@StringLength,'')) + 
					' (' + @ProcName + '-4).';
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
	end;
	-- OK, we have the character position that we will replace with a number
	set @ReplacingcharacterId = @RandomNumber;

	-- save this value for later so we can detect clashes when forcing both a number and a special character
	set @ForcedNumberPosition = @RandomNumber;


	--  Now get the row number of the actual number that we will add to the password...
	--  Get the id values for all Numbers...
	select @MinValue = min(id), @MaxValue = max(id)
	from @characters 
	where charType = 'Number';

	exec dbo.[prcGetRandomInteger] @RandomNumber OUT, @MinValue=@MinValue, @MaxValue=@MaxValue, @print='N', @Debug=@Debug2;
	if not @RandomNumber between @MinValue and @MaxValue
	begin;
		set @strMsg = 'ERROR: Invalid random number generated. ' + convert(varchar(10),isnull(@RandomNumber,'')) + 
					' should be between ' + convert(varchar(10),isnull(@MinValue,'')) + ' and ' + convert(varchar(10),isnull(@MaxValue,'')) + 
					' (' + @ProcName + '-3).';
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
	end;

	if @Debug = 'Y'
		print 'Forcing replace of char ' + convert(varchar(10),@ReplacingcharacterId) + ' with number from row ''' + convert(varchar(10),@RandomNumber) + '''...';

	-- And replace random string table record number @ReplacingcharacterId with this one
	update @RandomStringTable 
	set	charType	= c.charType,
		charValue	= c.charValue,
		charName	= c.charName
	from @RandomStringTable s
	join @characters c
		on s.id = @ReplacingcharacterId
		and c.id = @RandomNumber;

	if @@rowcount = 0
	begin;
		set @strMsg = 'ERROR: Internal error in ' + @ProcName + ': No matching record found with id matching randomly generated number ' + convert(varchar(10),isnull(@RandomNumber,'')) + ' when replacing character id #' + convert(varchar(10),isnull(@ReplacingcharacterId,'')) + ' (Err4).';
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
	end;
end;

-- =========================================================================
-- If we were asked to ensure there is at least one special character in it, check this now...
--
--  now if we need to force at least one special character, then do so if we havent already got a number
if @ForceAtLeastOneSpecialchar = 'Y' and @StringLength >= 3 and not exists (select 1 from @RandomStringTable where charType = 'Special')
begin;
	--
	-- We need to replace one of the characters with a special character
	--
	set @RandomNumber = @ForcedNumberPosition;	-- so we enter the loop at least once
	set @ClashCount = 0;
	-- loop until we have a number that is NOT the same as the @ForcedNumberPosition (i.e. a different character position that the forced number above)
	while @RandomNumber = @ForcedNumberPosition
	begin;
		--
		-- Which character should we replace? Get a random number in the range of 2 to password length (we never replace the first character)
		--
		exec dbo.[prcGetRandomInteger] @RandomNumber OUT, @MinValue=2, @MaxValue=@StringLength, @print='N', @Debug=@Debug2;
		if not @RandomNumber between 2 and @StringLength
		begin;
			set @strMsg = 'ERROR: Invalid random number generated. ' + convert(varchar(10),isnull(@RandomNumber,'')) + 
						' should be between 2 and ' + convert(varchar(10),isnull(@StringLength,'')) + 
						' (' + @ProcName + '-5).';
			exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
			return 1;
		end;
		--
		--  Is this position the same as the one we just forced a number into? If so, this is a 'clash' and we must re-try
		if @RandomNumber = @ForcedNumberPosition
		begin;
			set @ClashCount = @ClashCount + 1;
			set @strMsg = 'Warning: String position clash. Have already forced a number into character position ' + convert(varchar(10),isnull(@RandomNumber,'')) + 
						' and when forcing a special character we hit the same position. Clash count=' + convert(varchar(10),@ClashCount) + '. Retrying...';
			exec dbo.prcLogMessage @strMsg , 'Warning', @ProcName=@ProcName;

			-- if we have clashed more than 50 times in a row, terminate with an error (prevent infinite loop)
			if @ClashCount > 50
			begin;
				set @strMsg = 'ERROR: Clashed more than 50 times when finding a character position to force a special character.';
				exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
				return 1;
			end;
		end;
	end;
	-- OK, we have the character position that we will replace with a special character
	set @ReplacingcharacterId = @RandomNumber;

	--  Now get the row number of the actual special character that we will add to the password...
	--  Get the id values for all Special Characters...
	select @MinValue = min(id), @MaxValue = max(id)
	from @characters 
	where charType = 'Special';

	exec dbo.[prcGetRandomInteger] @RandomNumber OUT, @MinValue=@MinValue, @MaxValue=@MaxValue, @print='N', @Debug=@Debug2;
	if not @RandomNumber between @MinValue and @MaxValue
	begin;
		set @strMsg = 'ERROR: Invalid random number generated. ' + convert(varchar(10),isnull(@RandomNumber,'')) + 
					' should be between ' + convert(varchar(10),isnull(@MinValue,'')) + ' and ' + convert(varchar(10),isnull(@MaxValue,'')) + 
					' (' + @ProcName + '-4).';
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
	end;

	if @Debug = 'Y'
		print 'Forcing replace of char ' + convert(varchar(10),@ReplacingcharacterId) + ' with special character from row ''' + convert(varchar(10),@RandomNumber) + '''...';

	-- And replace random string table record number @ReplacingcharacterId with this one
	update @RandomStringTable 
	set	charType	= c.charType,
		charValue	= c.charValue,
		charName	= c.charName
	from @RandomStringTable s
	join @characters c
		on s.id = @ReplacingcharacterId
		and c.id = @RandomNumber;

	if @@rowcount = 0
	begin;
		set @strMsg = 'ERROR: Internal error in ' + @ProcName + ': No matching record found with id matching randomly generated number ' + convert(varchar(10),isnull(@RandomNumber,'')) + ' when replacing character id #' + convert(varchar(10),isnull(@ReplacingcharacterId,'')) + ' (Err5).';
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
	end;
end;

-- =========================================================================
--  And finally, extract the actual generated string value and it's phonetic equivilent
--
select @RandomString = '';
select @RandomStringPhonetic = '';

select @RandomString = @RandomString + charValue, @RandomStringPhonetic = @RandomStringPhonetic + charName + ' '
from @RandomStringTable
order by id;

-- and one last final check...
if len(@RandomString) <> @StringLength
begin;
		set @strMsg = 'ERROR: Internal error in ' + @ProcName + ': Expected string length of ' +  convert(varchar(10),@StringLength) + ', but found ' + convert(varchar(10),isnull(len(@RandomString),'')) + '.';
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
end;


-- =========================================================================
-- All done.
--
EndOfProc:
select @j = datalength(@RandomString);
if @Debug = 'Y' or @print = 'Y'
begin;
	print 'Generated String: ' + @RandomString + ' (len=' + convert(varchar(10),len(@RandomString)) + ').';
	print 'Phonetic        : ' + @RandomStringPhonetic;
end;



GO
-- ======================================================================================================================
set ANSI_NULLS ON;
set QUOTED_IDENTIFIER ON
go
if object_id('[dbo].[prcCheckTDE]') is null
	exec ('create procedure [dbo].[prcCheckTDE] as print ''Dummy proc.'' ');
GO

alter procedure [dbo].[prcCheckTDE]
as
/************************************************************************************************
	
************************************************************************************************/

select db_name(DB.database_id) as DBName, isnull(CER.name, 'Not Encrypted') as [Encrypted By Certificate], start_date, expiry_date,
		'Encryption_Status' = dbo.fnGetEncryptionStateDescription (encryption_state), percent_complete, recovery_model_desc as 'DBRecoveryModel'
from master.sys.databases DB
left join master.sys.dm_database_encryption_keys DEK 
	on DB.database_id = DEK.database_id
left join master.sys.certificates CER
	on DEK.encryptor_thumbprint =CER.thumbprint
where db_name(DB.database_id) not in ('master', 'model', 'msdb','tempdb')
order by 1;

GO

-- ======================================================================================================================
set ANSI_NULLS ON;
set QUOTED_IDENTIFIER ON;
GO
if object_id('[dbo].[prcTurnOffTDE]') is null
	exec ('create procedure [dbo].[prcTurnOffTDE] as print ''Dummy proc.'' ');
go
alter procedure [dbo].[prcTurnOffTDE]
(
	@DBNameSearch sysname = '%'
)
as
/************************************************************************************************
	Routine to turn off TDE encryption for a single database.
	- Turns encryption off (if necessary)
	- Waits for the encryption change to complete (if necessary)
	- Drops the DEK (if necessary)

************************************************************************************************/

set nocount on ;
Declare @STATE_NoEncryptionKey				int = 0;
Declare @STATE_Unencrypted					int = 1;
Declare @STATE_EncryptionInProgress			int = 2;
Declare @STATE_Encrypted					int = 3;
Declare @STATE_KeyChangeInProgress			int = 4;
Declare @STATE_DecryptionInProgress			int = 5;
Declare @STATE_ProtectionChangeInProgress	int = 6;

Declare @rc					int;
Declare @strMsg				varchar(4000);
Declare @State				int;
Declare @DBName				sysname;
Declare @SQL				nvarchar(1000);
Declare @DBCnt				int				= 0;
Declare @delayTime			varchar(20)		= '00:00:05';
Declare @ProcName			sysname			= object_name(@@procid);
exec dbo.prcLogMessage '<LogProcStartMsg>', @ProcName=@ProcName;

-- check user is sysadmin
if isnull(is_srvrolemember('sysadmin'),-1) <> 1
begin;
	exec dbo.prcLogMessage 'ERROR: You must be a member of the sysadmin server role to run this routine.', 'Error', @ProcName=@ProcName;
	return 1;
end;

set @strMsg = '- This script will turn TDE OFF for database(s): ' + isnull(@DBNameSearch,'<null>');
exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

Declare DBnames_cursor cursor for
select name 
from master.dbo.sysdatabases 
where name not in('master', 'model', 'msdb','tempdb')
and name like isnull(@DBNameSearch, '%')
order by 1;

Open DBnames_cursor;

while 1 = 1
begin;
	fetch next from DBnames_cursor INTO @DBName;
	if @@fetch_status <> 0 break;
	set @DBCnt = @DBCnt + 1;

	set @strMsg = '- Processing database "' + @DBName + '"...';
	exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;


	----------------------------------------------------------------------------------
	--  Un-Encrypt the database if necessary
	UnencryptDB:

	select @State = encryption_state
	from master.sys.dm_database_encryption_keys 
	where db_name(database_id) = @DBName ;

	if @@rowcount = 0 or @State is null
		set @State = @STATE_NoEncryptionKey;

	-- if the database is currently undergoing an encryption state change, wait a bit then check again
	if @State in (@STATE_EncryptionInProgress, @STATE_DecryptionInProgress, @STATE_KeyChangeInProgress, @STATE_ProtectionChangeInProgress)
	begin;
		set @strMsg = '  - Database ' + @DBName + ' is currently undergoing an encryption state change (state=' + dbo.fnGetEncryptionStateDescription(@State) + '). Waiting...';
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
		waitfor delay @delayTime;
		goto UnencryptDB;
	end;

	if @State = @STATE_NoEncryptionKey or @State = @STATE_Unencrypted
	begin;
		set @strMsg = '  - Database ' + @DBName + ' is already not encrypted (state=' + dbo.fnGetEncryptionStateDescription(@State) + ') - no decryption necessary.';
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	end;
	else if @State = @STATE_Encrypted
	begin;
		--The following code tries to sets TDE encryption OFF in that DB
		begin try;

			set @SQL = 'ALTER DATABASE [' + @DBName +'] SET ENCRYPTION OFF;' ;

			set @strMsg = '  - Turning TDE encryption OFF for Database: ' + @DBName  + ' (SQL=' + @SQL + ').';
			exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

			exec (@SQL);

		end try
		begin catch;
			set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' setting encryption off for database ' + @DBName + ': ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
			if ERROR_NUMBER() = 5069
				set @strMsg = @strMsg + '. This can occur when the database has changes from previous encryption scans that are pending log backup. Take a log backup and retry the command.'
			exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
			close DBnames_cursor ;
			deallocate DBnames_cursor ;
			return 1;
		end catch;
	end;
	else
	begin;
		set @strMsg = 'ERROR: Unexpected database encryption state "' + isnull(convert(varchar(10),@State),'<null>') + '" (' + dbo.fnGetEncryptionStateDescription(@State) + ') for database ' + @DBName ;
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		close DBnames_cursor ;
		deallocate DBnames_cursor ;
		return 1;
	end;


	----------------------------------------------------------------------------------
	--  Drop the DEK if necessary
	DropDEK:
	select @State = encryption_state
	from master.sys.dm_database_encryption_keys 
	where db_name(database_id) = @DBName ;

	if @@rowcount = 0 or @State is null
		set @State = @STATE_NoEncryptionKey;

	-- if the database is currently undergoing an encryption state change, wait a bit then check again
	if @State in (@STATE_EncryptionInProgress, @STATE_DecryptionInProgress, @STATE_KeyChangeInProgress, @STATE_ProtectionChangeInProgress)
	begin;
		set @strMsg = '  - Database ' + @DBName + ' is currently undergoing an encryption state change (state=' + dbo.fnGetEncryptionStateDescription(@State) + '). Waiting...';
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
		waitfor delay @delayTime;
		goto DropDEK;
	end;

	if @State = @STATE_NoEncryptionKey
	begin;
		set @strMsg = '  - Database ' + @DBName + ' already has no DEK (state=' + dbo.fnGetEncryptionStateDescription(@State) + ') - no drop DEK necessary.';
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	end;
	else if @State = @STATE_Unencrypted
	begin;
		--The following code tries to sets TDE encryption OFF in that DB
		begin try;

			set @SQL = 'USE [' + @DBName + ']; DROP DATABASE ENCRYPTION KEY;' ;

			set @strMsg = '  - Dropping DEK for Database: ' + @DBName  + ' (SQL=' + @SQL + ').';
			exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

			exec (@SQL);

		end try
		begin catch;
			set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' dropping DEK for database ' + @DBName + ': ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
			exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
			close DBnames_cursor ;
			deallocate DBnames_cursor ;
			return 1;
		end catch;
	end;
	else
	begin;
		set @strMsg = 'ERROR: Unexpected database encryption state "' + isnull(convert(varchar(10),@State),'<null>') + '" (' + dbo.fnGetEncryptionStateDescription(@State) + ') for database ' + @DBName ;
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		close DBnames_cursor ;
		deallocate DBnames_cursor ;
		return 1;
	end;
end;

close DBnames_cursor ;
deallocate DBnames_cursor ;

if @DBCnt = 0
begin;
	set @strMsg = 'ERROR: No user databases match name ''' + @DBNameSearch + '''.';
	exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
	return 1;
end;

set @strMsg =  '- TDE Turnoff complete. Processed ' + isnull(convert(varchar(10),@DBCnt),'<null>') + ' databases.';
exec dbo.prcLogMessage @strMsg , @ProcName=@ProcName;

ExitWithSuccess:
exec dbo.prcLogMessage '<LogProcEndMsg>', @ProcName=@ProcName;

GO

-- ======================================================================================================================
set ANSI_NULLS ON;
set QUOTED_IDENTIFIER ON;
GO
if object_id('[dbo].[prcChangeTDEPassword]') is null
	exec ('create procedure [dbo].[prcChangeTDEPassword] as print ''Dummy proc.'' ');
go
alter procedure [dbo].[prcChangeTDEPassword]
(
	@Password				sysname = null out,
	@SkipPasswordGeneration	char(1) = 'N'
)
with encryption 
as
/************************************************************************************************
	Routine to change the TDE password
	- Generates a new random password (if @SkipPasswordGeneration <> 'Y')
	- Saves the password in tblTDEData
	- Call the proc to update the DMK to be encrypted by this new password 

	

************************************************************************************************/

set nocount on ;
Declare	@rc						int;
Declare @strMsg					varchar(4000);
Declare @SQL					nvarchar(1000);
Declare @PasswordPhonetic		varchar(1000) = '';
Declare @Asterisks				char(8) = '********';
Declare @SkipAlterMasterKeyStep	char(1) = 'N';
Declare @BinaryConstant			varbinary (100) = 0x0A23453BDEA5C8B225D88C152E8399F147F25F6DC3C5600B3ACA42B12645640021ABA4AF5D6046C85A0B521DAE232398CC21;
Declare @Replace				sysname;
Declare @ProcName				sysname			= object_name(@@procid);
exec dbo.prcLogMessage '<LogProcStartMsg>', @ProcName=@ProcName;

-- check user is sysadmin
if isnull(is_srvrolemember('sysadmin'),-1) <> 1
begin;
	exec dbo.prcLogMessage 'ERROR: You must be a member of the sysadmin server role to run this routine.', 'Error', @ProcName=@ProcName;
	return 1;
end;

----------------------------------------------------------------------------------
-- If they asked to Skip New Password Generation, then verify that they passed in the password they want to use.
if upper(@SkipPasswordGeneration) = 'Y'
begin;
	set @SkipPasswordGeneration = 'Y'	-- force case on case-sensitive instances
	if isnull(@Password,'') = ''
	begin;
		set @strMsg = 'ERROR: When calling ' + @ProcName + ', if you specify @SkipPasswordGeneration = ''Y'' then you must also specify a non-blank @Password value.';
		exec dbo.prcLogMessage @strMsg, 'Error', @ProcName=@ProcName;
		return 1;
	end;
end;
else if upper(@SkipPasswordGeneration) = 'N'
begin;
	set @Password = '';
end;
else
begin;
	set @strMsg = 'ERROR: Unknown value for @SkipPasswordGeneration parameter passed to ' + @ProcName + '. Must be ''Y'' or ''N'', not ''' + isnull(convert(varchar(10),@SkipPasswordGeneration),'<null>') + '''.';
	exec dbo.prcLogMessage @strMsg, 'Error', @ProcName=@ProcName;
	return 1;
end;

----------------------------------------------------------------------------------
--  Generate a new random password...
--

if @SkipPasswordGeneration = 'Y'
begin;
	exec dbo.prcLogMessage '- Skipping generation of new password because @SkipPasswordGeneration = ''Y''.', @ProcName=@ProcName;
end;
else
begin;
	--  Generate a new random password...

	exec dbo.prcLogMessage '- Generating a new password.', @ProcName=@ProcName;

	-- generate a random password...
	exec @rc = dbo.prcGetRandomString @Password out, @PasswordPhonetic out,
					@MinLength		= 15,
					@MaxLength		= 15,
					@ForceAtLeastOneNumber		= 'Y',
					@ForceAtLeastOneSpecialchar	= 'Y';

	select @rc = isnull(@rc,0) + @@error;
	if @rc <> 0
	begin;
		set @strMsg = 'ERROR: Proc ''prcGetRandomString'' terminated with RC=' + isnull(convert(varchar(10),@rc),'<null>') + '.';
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
	end;

	-- check password is not blank
	if isnull(@Password, '') = ''
	begin;
		set @strMsg = 'ERROR: The generated password is null or blank.';
		exec dbo.prcLogMessage @strMsg, 'Error', @ProcName=@ProcName;
		return 1;
	end;

end;
set @Replace = substring(@Password, 1, 2) + replicate('*', len(@Password) - 4) + substring(@Password, len(@Password)-1, 2);

----------------------------------------------------------------------------------
--  We do the updates within a transaction so it is either all comitted or all rolled back

BEGIN TRANSACTION;


----------------------------------------------------------------------------------
-- save the generated password...
insert into dbo.tblTDEData (RecordType, Value)
values ('Data', convert(varbinary(128),EncryptByPassPhrase(@BinaryConstant, @Password, 0, null)));

set @rc = @@error;
if @rc <> 0
begin;
	set @strMsg = 'ERROR: Error ' + convert(varchar(10),@rc) + ' inserting record into tblTDEData.';

	ROLLBACK;

	exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
	exec dbo.prcLogMessage 'NOTE: Any changes made by this proc have been rolled back!', @ProcName=@ProcName;

	return 1;
end;



print replicate('*',150)
print replicate('*',150)
print substring('***  New TDE Password is: ' + @Password + replicate(' ',150), 1, 147) + '***'
if @PasswordPhonetic <> ''
	print substring('***                     : ' + @PasswordPhonetic + replicate(' ',150), 1, 147) + '***';
print substring('***' + replicate(' ',150), 1, 147) + '***';
print substring('***  NOTE: Please ensure this password is recorded and securely stored as per the Yuvan SQL Server TDE documentation. ' + replicate(' ',150), 1, 147) + '***';
print substring('***  Otherwise it might not be possible to recover encrypted databases from this server in the future. ' + replicate(' ',150), 1, 147) + '***';
print substring('***' + replicate(' ',150), 1, 147) + '***';
print replicate('*',150)
print replicate('*',150)


----------------------------------------------------------------------------------
-- Update the DMK to be encrypted by the new password
-- first, check if the DMK already exists...

if exists (select * from [master].[sys].[symmetric_keys] where [name] = '##MS_DatabaseMasterKey##')
begin;
	----------------------------------------------------------------------------------
	-- Check that the password has not already been used before.  If it has then we cant add it again.
	-- We first check that this password has not been used before.
	-- This is most critical when we are using a user-supplied password, since it's extremely unlikely that a randomly generated password would have 
	--    been used before, but it cant hurt to check it in both cases
	begin try;

		set @SQL = 'USE [master]; OPEN MASTER KEY DECRYPTION BY PASSWORD = ''' + isnull(@Password,'''No Password''') + ''' ';
		exec (@SQL);

		set @strMsg =  '- The DMK is already encrypted by this password. This password has been used before.  No need to update the DMK.';
		exec dbo.prcLogMessage @strMsg , @ProcName=@ProcName;
		set @SkipAlterMasterKeyStep = 'Y'

	end try
	begin catch;
		if ERROR_NUMBER() = 15313
		begin;
			set @strMsg =  '- The DMK is not already encrypted by this password. This password has not been used before.';
			exec dbo.prcLogMessage @strMsg , @ProcName=@ProcName;
		end;
		else
		begin;
			set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' checking if the password has been used before on the DMK: ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
			set @strMsg = replace(@strMsg, @Password, @Asterisks);	-- ensure we dont log the password

			ROLLBACK;

			exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
			exec dbo.prcLogMessage 'NOTE: Any changes made by this proc have been rolled back!', @ProcName=@ProcName;

			return 1;
		end;
	end catch;


	--
	----------------------------------------------------------------------------------
	-- Modify the DMK to specify the new password...
	
	if @SkipAlterMasterKeyStep = 'N'
	begin;
		begin try;

			set @SQL = 'USE [master]; ALTER MASTER KEY ADD ENCRYPTION BY PASSWORD = ''' + isnull(@Password,'''No Password''') + ''' ';
			set @strMsg = '- Adding password to existing DMK. (SQL=' + replace(@SQL, @Password, @Replace) + ').';
			exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	
			exec (@SQL);

		end try
		begin catch;
			set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' altering the Database Master Key (DMK): ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
			set @strMsg = replace(@strMsg, @Password, @Asterisks);	-- ensure we dont log the password

			ROLLBACK;

			exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
			exec dbo.prcLogMessage 'NOTE: Any changes made by this proc have been rolled back!', @ProcName=@ProcName;

			return 1;
		end catch;
	end;
end;
else
begin;
	-- DMK does not exist - create it
	begin try;

		set @SQL = 'USE [master]; CREATE MASTER KEY ENCRYPTION BY PASSWORD = ''' + isnull(@Password,'''No Password''') + ''' ';
		set @strMsg = '- Creating Database Master Key (DMK), encrypted by password. (SQL=' + replace(@SQL, @Password, @Replace) + ').';
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	

		exec (@SQL);

	end try
	begin catch;
		set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' creating Database Master Key (DMK): ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
		set @strMsg = replace(@strMsg, @Password, @Asterisks);	-- ensure we dont log the password

		ROLLBACK;

		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		exec dbo.prcLogMessage 'NOTE: Any changes made by this proc have been rolled back!', @ProcName=@ProcName;
		return 1;
	end catch;

end;

----------------------------------------------------------------------------------
-- Commit changes
begin try;

	COMMIT;

end try
begin catch;
	set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' creating Database Master Key (DMK): ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
	set @strMsg = replace(@strMsg, @Password, @Asterisks)	-- ensure we dont log the password;


	if @@trancount > 0
		ROLLBACK;

	exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;

	return 1;
end catch;


set @strMsg = '- TDE password changed OK.';
exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

exec dbo.prcLogMessage '<LogProcEndMsg>', @ProcName=@ProcName;

GO




-- ======================================================================================================================
set ANSI_NULLS ON;
set QUOTED_IDENTIFIER ON;
GO
if object_id('[dbo].[prcBackupTDEKeys]') is null
	exec ('create procedure [dbo].[prcBackupTDEKeys] as print ''Dummy proc.'' ');
go
alter procedure [dbo].[prcBackupTDEKeys]
(
	@KeyBackupRetentionDays		int = 14,
	@LogRecordRetentionDays		int = 30
)
with encryption 
as
/************************************************************************************************
	Routine to backup the SMK, DMK and all TDE certificates.
	- Get the TDE password
	- Checks the password currently encrypts the DMK
	- Backup the SMK, protecting files by the TDE password
	- Backup the DMK, protecting files by the TDE password
	- Backup all Certificates that could be used for TDE, including their private keys. Protects files using the TDE password
	- Deletes SMK, DMK or Certificate backup files that are older than the nubmer of days specified in @KeyBackupRetentionDays (as long as a later backup of that object exists)
	- Deletes tblMessageLog records that are older than the nubmer of dats specified in @LogRecordRetentionDays where the message was
		logged by this proc running as a SQL Agent job (prevents this database drowing too big)


	

************************************************************************************************/

set nocount on;
Declare @InstanceName		sysname;
Declare @InstanceId			sysname	;
Declare @DefaultBackupPath	varchar(128);
Declare @SQLRegistryKey		varchar(128);
Declare @Datetime			char(14);
Declare @StrHour			varchar(2);
Declare @StrMin				varchar(2);
Declare @CertName			sysname;
Declare @FName				varchar(1000);
Declare @FName2				varchar(1000);
Declare @SQL				nvarchar(4000);
Declare @FileNamePart		sysname;
Declare @strMsg				varchar(4000);
Declare @FileDate			datetime;
Declare @FileNameWithoutDate varchar(1000);
Declare @rc					int;
Declare @Cnt				int;
Declare @Password			sysname;
Declare @LogRecordRetentionDate datetime;
Declare @KeyBackupRetentionDate datetime;
Declare @FullServerName		sysname			= replace(@@servername, '\', '_');
Declare @Asterisks			char(8)			= '********';
Declare @BinaryConstant		varbinary(100)	= 0x0A23453BDEA5C8B225D88C152E8399F147F25F6DC3C5600B3ACA42B12645640021ABA4AF5D6046C85A0B521DAE232398CC21;
Declare @CertCnt			int				= 0;
Declare @ProcName			sysname			= object_name(@@procid);
exec dbo.prcLogMessage '<LogProcStartMsg>', @ProcName=@ProcName;

-- check user is sysadmin
if isnull(is_srvrolemember('sysadmin'),-1) <> 1
begin;
	exec dbo.prcLogMessage 'ERROR: You must be a member of the sysadmin server role to run this routine.', 'Error', @ProcName=@ProcName;
	return 1;
end;

-------------------------------------------------------------------
-- First, generate a timestamp for the backup files, and find the default backup location

--Get the DateTime Value in YYYYMMDDHHSS Format
select @Datetime = replace(replace(replace(convert(varchar(30),getdate(),120 ),'-',''),':',''),' ','');

--  Get the Instance Name
select @InstanceName = convert(sysname,serverproperty('InstanceName'));
if @InstanceName is null
	select @InstanceName = 'MSSQLSERVER';
	
-- Get the default SQL backup folder path from registry
-- First, locate the instance ID
exec master.dbo.xp_regread 	'HKEY_LOCAL_MACHINE', 
				'SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL',
				@InstanceName,
				@InstanceId out;
				
-- now find the default backup path
set @SQLRegistryKey = 'SOFTWARE\Microsoft\Microsoft SQL Server\' + @InstanceId + '\MSSQLServer';
exec master.dbo.xp_regread 	'HKEY_LOCAL_MACHINE', 
				@SQLRegistryKey,
				'BackupDirectory',
				@DefaultBackupPath out;
	
set @DefaultBackupPath = @DefaultBackupPath + '\';

set @strMsg = '- Default backup path is:' + isnull(@DefaultBackupPath,'<null>');
exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
set @strMsg = '- Timestamp for this run is:' + isnull(@Datetime,'<null>');
exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;


-------------------------------------------------------------------
-- Get the DTE password for this server

select top 1 @Password = convert(sysname, DecryptByPassPhrase(@BinaryConstant, convert(varbinary(128),Value), 0, null))
from dbo.tblTDEData
where RecordType = 'Data'
order by id desc;

-- if we didnt find a password record, we cant continue
if @@RowCount = 0 or @Password is null
begin;
	set @strMsg = 'ERROR: The TDE password does not exist or is not known. Cannot produce TDE key backups.';
	exec dbo.prcLogMessage @strMsg, 'Error', @ProcName=@ProcName;
	return 1;
end;



----------------------------------------------------------------------------------
-- Check that this password is the same as the DMK password...
-- Try to Open the DMK that's protected by password;


begin try;

	set @SQL = 'USE [master]; OPEN MASTER KEY DECRYPTION BY PASSWORD = ''' + isnull(@Password,'''No Password''') + '''';
	set @strMsg = '- Opening DMK using password. (SQL=' + replace(@SQL, @Password, @Asterisks) + ').';
	exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	
	exec (@SQL);

end try
begin catch;
	set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' opening Database Master Key (DMK): ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
	set @strMsg = replace(@strMsg, @Password, @Asterisks);	-- ensure we dont log the password
	exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;

	set @strMsg = 'ERROR: The DMK can not be decrypted using the password. You should configure a new TDE password using stored procedure prcChangeTDEPassword.';
	exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
	-- 	return 1 we continue on backup failure...
end catch;



-- ----------------------------------------------------------------
-- The following code Backup the Service Master key [SMK]:

begin try;

	set @FName  = @FullServerName + '.$ServiceMasterKey$.' + @Datetime + '.bak';

	set @strMsg = '- Backing up the Service Master Key (SMK) to: ' + @DefaultBackupPath + @FName;
	exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

	set @SQL = 'USE [master]; '
				+ ' BACKUP SERVICE MASTER KEY TO FILE = ''' + @DefaultBackupPath + @FName + ''' '
				+ ' ENCRYPTION BY PASSWORD = ''' + isnull(@Password,'''No Password''') + ''' ';

	exec (@SQL);

end try
begin catch;
	set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' backing up the SMK: ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
	set @strMsg = replace(@strMsg, @Password, @Asterisks);	-- ensure we dont log the password
	exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
	-- 	return 1 we continue on backup failure...
end catch;


-- ----------------------------------------------------------------
-- The following code Backup the database master key [DMK]:

begin try;

	set @FName  = @FullServerName + '.$DatabaseMasterKey$.' + @Datetime + '.bak';

	set @strMsg = '- Backing up the Database Master Key (DMK) to: ' + @DefaultBackupPath + @FName;
	exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

	set @SQL = 'USE [master]; '
				+ ' BACKUP MASTER KEY TO FILE = ''' + @DefaultBackupPath + @FName + ''' '
				+ ' ENCRYPTION BY PASSWORD = ''' + isnull(@Password,'''No Password''')  + ''' ';

	exec (@SQL);

end try
begin catch
	set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' backing up the DMK: ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
	set @strMsg = replace(@strMsg, @Password, @Asterisks);	-- ensure we dont log the password
	exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
	-- 	return 1 we continue on backup failure...
end catch;


-- ----------------------------------------------------------------
-- The following code backs up all Certificates that are eligible for use with TDE, along with their private key:

set @CertCnt = 0;
exec dbo.prcLogMessage '- Backing up TDE Certificates...', @ProcName=@ProcName;

Declare Certificates_cursor cursor for
select name 
from master.sys.certificates
where pvt_key_encryption_type_desc = 'ENCRYPTED_BY_MASTER_KEY'
order by 1;

Open Certificates_cursor;

while 1 = 1
begin;
	fetch next from Certificates_cursor INTO @CertName;
	if @@fetch_status <> 0 break;

	set @CertCnt = @CertCnt + 1;

	begin try;

		-- Ensure there are no special characters in the file name..
		set @FileNamePart = replace(replace(@CertName, '\', '_'), '/', '_') ;
		set @FName  = @FullServerName + '.$Certificate$.' + @FileNamePart + '.' + @Datetime + '.cer';
		set @FName2 = @FullServerName + '.$Certificate$.' + @FileNamePart + '.' + @Datetime + '.pvk';

		set @strMsg = '  - Backing up certificate ''' + @CertName + ''' to: ' + @DefaultBackupPath + @FName + ', and private key to: ' + @FName2;
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;



		set @SQL = 'USE [master]; '
				 + ' BACKUP CERTifICATE [' + @CertName + '] TO FILE = ''' + @DefaultBackupPath + @FName + ''' '
				 + ' WITH PRIVATE KEY (FILE= ''' + @DefaultBackupPath + @FName2 + ''', '
							+ ' ENCRYPTION BY PASSWORD = ''' + isnull(@Password, '''No Password''') + ''' ) ';

		exec (@SQL);

	end try
	begin catch;
		set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' backing up certificate "' + isnull(@CertName,'<null>') + '": ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
		set @strMsg = replace(@strMsg, @Password, @Asterisks);	-- ensure we dont log the password
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		-- 	return 1 we continue on backup failure...
	end catch;


end;
close Certificates_cursor;
deallocate Certificates_cursor;

if @CertCnt = 0
begin;
	set @strMsg = 'ERROR: No TDE certificates found. TDE configuration is not complete.';
	exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
	return 1;
end;


set @strMsg =  '- Backed up ' + isnull(convert(varchar(10),@CertCnt),'<null>') + ' TDE certificates OK.';
exec dbo.prcLogMessage @strMsg , @ProcName=@ProcName;


-- ----------------------------------------------------------------
-- delete old backups 
--  Delete the OLD Backups of SMK, DMK and Certificate files from the backup folder, where the Ready to Archive attribute is set.

select @KeyBackupRetentionDate = convert(datetime, convert(char(10), dateadd(day, 0 - @KeyBackupRetentionDays, getdate()), 120));

set @strMsg = '- Deleting key and certificate backups more than ' + convert(varchar(10),@KeyBackupRetentionDays, 120) + ' days old (created before ' + convert(varchar(10),@KeyBackupRetentionDate, 120) + ').';
exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

-- set @SQL = 'DIR /A-A /B "' +@DefaultBackupPath + '" ' ?????? archive attribute check ????
set @SQL = 'DIR /B "' +@DefaultBackupPath + '" ';
CREATE TABLE #FileList 
(FName					varchar(1000) null,
 DateValue				datetime null,
 FileNameWithoutDate	varchar(1000) null,
 WorkingValue			varchar(1000) null
) ;

INSERT #FileList  (FName)
execute master.dbo.xp_cmdshell @SQL;

delete from #FileList where FName is NULL or FName = '';

delete from #FileList
where FName not like @FullServerName + '%$ServiceMasterKey$%.bak%'
  and FName not like @FullServerName + '%$DatabaseMasterKey$%.bak%'
  and FName not like @FullServerName + '%$Certificate$%.cer%'
  and FName not like @FullServerName + '%$Certificate$%.pvk%';

-- reverse the file name...
update #FileList
set WorkingValue = reverse(FName);


-- Extract the date. Skip the first 4 characters (the file extension - e.g. '.cer'), and take the next 14 characters.  If this is a standard backup file, this string will be in the format 'YYYYMMDDHHIISS'
update #FileList
set WorkingValue = reverse(substring(WorkingValue, 5, 14))
where charindex('.', WorkingValue) >= 4;

-- Convert this to a date in format YYYY-MM-DD HH:II:SS
update #FileList
set WorkingValue = stuff(stuff(stuff(stuff(stuff(WorkingValue, 5, 0, '-'), 8, 0, '-'), 11, 0, ' '), 14, 0, ':'), 17, 0, ':'),
	FileNameWithoutDate = replace(FName, WorkingValue, '<date>');

-- When this value is a valid date, save it
update #FileList
set DateValue = convert(datetime, WorkingValue)
where isdate(WorkingValue) = 1;


-- list all files that have a date/time stamp before the date we are deleting from

Declare curDir cursor for
select FName, DateValue, FileNameWithoutDate 
from #FileList
where DateValue <= @KeyBackupRetentionDate
order by 1;


OPEN curDir ;

set @Cnt = 0;

while 1 = 1
begin ;

	fetch curDir into @FName, @FileDate, @FileNameWithoutDate ;
	if @@fetch_status <> 0 break;
	
	-- We only delete the file if there is another file for the same object that was created later
	if not exists (select 1 
					from #FileList
					where FileNameWithoutDate = @FileNameWithoutDate	-- a backup file for the same object
					  and  DateValue > @FileDate						--  that was created more recently
					)
	begin;
		set @strMsg = '  - not deleting this file because no more recent backups exist of the same object: ' + @FName;
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	end;
	else
	begin;
		set @strMsg = '  - Deleting old backup file: ' + @DefaultBackupPath + @FName;
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
		
		set @Cnt = @Cnt + 1;
		set @SQL = 'DEL "' + @DefaultBackupPath + @FName + '"';

		exec @rc = master..xp_cmdshell @SQL, no_output;
		set @rc = isnull(@rc,0) + @@error;
		if @rc <> 0 
		begin ;
			set @strMsg = 'Error while deleting file: '+ @DefaultBackupPath + @FName;
			exec dbo.prcLogMessage @strMsg, 'Error', @ProcName=@ProcName;
		end;
		else
		begin;
			set @strMsg = '  - Deleted ' + @FName + ' OK.';
			exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
		end;
	end;
end;
set @strMsg = '- Deleted ' + convert(varchar(10),@Cnt) + ' key or certificate backup files.';
exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

CLOSE curDir ;
deallocate curDir ;
DROP TABLE #FileList ;



-- ----------------------------------------------------------------
-- Delete old Log message records

-- get the date that we'll remove records before...
select @LogRecordRetentionDate = convert(datetime, convert(char(10), dateadd(day, 0 - @LogRecordRetentionDays, getdate()), 120));

set @strMsg = '- Deleting tblMessageLog records more than ' + convert(varchar(10),@LogRecordRetentionDays, 120) + ' days old (created before ' + convert(varchar(10),@LogRecordRetentionDate, 120) + ').';
exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

delete from dbo.tblMessageLog
where MessageTime <= @LogRecordRetentionDate
  and ProcName = @ProcName	-- record is from this backup proc
  and (LoggingProgram like '%SQLAgent%' or LoggingProgram like '$SQL Agent%' or LoggingProgram like '$SQL Server Agent%')

select @rc = @@error, @Cnt = @@rowcount;

if @rc <> 0
begin;
	exec dbo.prcLogMessage 'ERROR: An error ocurred deleting old tblMessageLog records!', 'Error', @ProcName=@ProcName;
	return 1;
end;
set @strMsg = '- Deleted ' + convert(varchar(10),@Cnt) + ' tblMessageLog records.';
exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

-- ----------------------------------------------------------------
exec dbo.prcLogMessage '<LogProcEndMsg>', @ProcName=@ProcName;

QUIT:
GO
-- ======================================================================================================================
set ANSI_NULLS ON;
set QUOTED_IDENTIFIER ON;
GO
if object_id('[dbo].[prcDeployTDE]') is null
	exec ('create procedure [dbo].[prcDeployTDE] as print ''Dummy proc.'' ');
go
alter procedure [dbo].[prcDeployTDE]
(
	@DBNameSearch 		sysname,
	@SkipPasswordGeneration	char(1) = 'N',
	@Password		sysname = null,  -- Allows you to specify which password to use when @SkipPasswordGeneration='Y'
	@Debug		 	char(1) = 'N'
)
with encryption 
as
/************************************************************************************************
	Routine to turn on TDE encryption for one or more databases.
	- Retrieves the TDE password, or generates a new one if none exists
	- Create the DMK (if necessary), encrypted by the password
	- Ensures the DMK is also encrypted by the SMK
	- Explicitly opens the DMK using the TDE password to verify that the password is correct
	- Create the certificate (if necessary), encrypted by the DMK 
	- for each database matching '@DBNameSearch'
		- Creates a DEK (if necessary), encrypted by the certificate
		- Turns encryption on (if necessary)
	- If any changes were made to the SMK, DEK or certificates, call the proc to back these up

	

************************************************************************************************/

set nocount on
Declare @STATE_NoEncryptionKey				int = 0;
Declare @STATE_Unencrypted					int = 1;
Declare @STATE_EncryptionInProgress			int = 2;
Declare @STATE_Encrypted					int = 3;
Declare @STATE_KeyChangeInProgress			int = 4;
Declare @STATE_DecryptionInProgress			int = 5;
Declare @STATE_ProtectionChangeInProgress	int = 6;

Declare @CertName			sysname;
Declare @strMsg				varchar(4000);
Declare @SQL				nvarchar(4000);
Declare @rc					int;
Declare @State				int;
Declare @DBName				sysname;
Declare @MakeNewPassword	int;
Declare @delayTime			varchar(20)		= '00:00:05';
Declare @BinaryConstant		varbinary(100)	= 0x0A23453BDEA5C8B225D88C152E8399F147F25F6DC3C5600B3ACA42B12645640021ABA4AF5D6046C85A0B521DAE232398CC21;
Declare @ChangesMade		int				= 0;
Declare @DBCnt				int				= 0;
Declare @PasswordPhonetic	varchar(1000);
Declare @Asterisks			char(8)			= '********';
Declare @Algorithm			nvarchar(60);
Declare @ProcName			sysname			= object_name(@@procid);
exec dbo.prcLogMessage '<LogProcStartMsg>', @ProcName=@ProcName;

-- check user is sysadmin
if isnull(is_srvrolemember('sysadmin'),-1) <> 1
begin;
	exec dbo.prcLogMessage 'ERROR: You must be a member of the sysadmin server role to run this routine.', 'Error', @ProcName=@ProcName;
	return 1;
end;

--Check the Edition
if convert(varchar(128),isnull(serverproperty('Edition'),'')) not like '%Enterprise Edition%'
begin;
	exec dbo.prcLogMessage 'ERROR: TDE can be implemented only on SQL Enterprise edition', 'Error', @ProcName=@ProcName;
	return 1;
end;

if @SkipPasswordGeneration = 'Y'
begin;
	if isnull(@Password,'') = ''
	begin;
		exec dbo.prcLogMessage 'ERROR: @Password must be specified when @SkipPasswordGeneration = ''Y''.', 'Error', @ProcName=@ProcName;
		return 1;
	end;
end;
else if @SkipPasswordGeneration = 'N'
begin;
	if isnull(@Password,'') <> ''
	begin;
		exec dbo.prcLogMessage 'ERROR: @Password cannot be specified when @SkipPasswordGeneration = ''N''.', 'Error', @ProcName=@ProcName;
		return 1;
	end;
	set @Password = '';
end;
else
begin;
	exec dbo.prcLogMessage 'ERROR: @SkipPasswordGeneration must be ''Y'' or ''N''.', 'Error', @ProcName=@ProcName;
	return 1;
end;


set @strMsg = '- This script will turn TDE ON for database(s): ' + isnull(@DBNameSearch,'<null>');
exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;


set @MakeNewPassword = 0;

-- Get any previously saved password...
select top 1 @Password = convert(sysname, DecryptByPassPhrase(@BinaryConstant, convert(varbinary(128),Value), 0, null))
from dbo.tblTDEData
where RecordType = 'Data'
order by id desc;

-- if we didnt find a previous password in tblTDEData, we need to create one
if @@RowCount = 0 or @Password is null
begin;
	exec dbo.prcLogMessage '- No previous password found - will now generate a new password & create/update the DMK.', @ProcName=@ProcName;
	set @MakeNewPassword = 1;
end;
else
	exec dbo.prcLogMessage '- Previous password retrieved OK.', @ProcName=@ProcName;

if not exists (select * from [master].[sys].[symmetric_keys] where [name] = '##MS_DatabaseMasterKey##')
begin;
	exec dbo.prcLogMessage '- DMK does not exist - will now generate a new password & create the DMK.', @ProcName=@ProcName;
	set @MakeNewPassword = 1;
end;
else
	exec dbo.prcLogMessage '- DMK exists OK.', @ProcName=@ProcName;

-- if wither of the above tests failed, then , generate a new password and store it and update the DMK
if @MakeNewPassword = 1
begin;
	exec dbo.prcLogMessage '- Calling proc to change TDE password.', @ProcName=@ProcName;
	
	exec @rc = dbo.prcChangeTDEPassword @Password out, @SkipPasswordGeneration;


	select @rc = isnull(@rc,0) + @@error;
	if @rc <> 0
	begin;
		set @strMsg = 'ERROR: Proc ''prcChangeTDEPassword'' terminated with RC=' + isnull(convert(varchar(10),@rc),'<null>') + '.';
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
	end;


	set @ChangesMade = @ChangesMade + 1;

end;


----------------------------------------------------------------------------------
-- Check that this password is the same as the DMK password...
-- Try to Open the DMK that's protected by password;

begin try;

	set @SQL = 'USE [master]; OPEN MASTER KEY DECRYPTION BY PASSWORD = ''' + isnull(@Password,'<null>') + '''';
	set @strMsg = '- Opening DMK using password. (SQL=' + replace(@SQL, isnull(@Password,'<null>'), @Asterisks) + ').';
	exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	
	exec (@SQL);

end try
begin catch;
	set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' opening Database Master Key (DMK): ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
	set @strMsg = replace(@strMsg, isnull(@Password,'<null>'), @Asterisks);	-- ensure we dont log the password
	exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;

	set @strMsg = 'ERROR: The DMK can not be decrypted using the password. You should configure a new TDE password using stored procedure prcChangeTDEPassword.';
	exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
	return 1;
end catch;



----------------------------------------------------------------------------------
-- Check the DMK is encrypted with SMK as well. If not, encrypt the DMK with the SMK as well
if (select is_master_key_encrypted_by_server  from sys.databases where name='master') !=1
begin;

	begin try;

		set @SQL = 'USE [master]; ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY;';
		set @strMsg = '- DMK is not currently encrypted by the SMK. Encrypting the DMK with the SMK. SQL=' + @SQL;
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	
		exec (@SQL);

	end try
	begin catch;
		set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' encrypting the DMK by the SMK: ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
	end catch;

	set @ChangesMade = @ChangesMade + 1;
end;



----------------------------------------------------------------------------------
--  Create the certificate if required

--Check if the certificate exists.
set @CertName = replace(@@servername,'\','_') + '_Certificate';

if exists (select * from master.sys.certificates where [name] = @CertName)
begin;
	set @strMsg = '- Certificate already exixts. Skipping Certificate creation: ' + @CertName;
	exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
end;
else
Begin;
	--Create a certificate protected by the master key 
	
	begin try;

		set @SQL =    'USE [master]; '
					+ 'CREATE CERTifICATE [' + @CertName + '] '
					+ ' WITH SUBJECT =  ''Certificate to TDE encrypt ' + @@ServerName + ' Databases'', EXPIRY_DATE = ''2100-01-01''; ';

		set @strMsg = '- Creating TDE Certificate ' + @CertName + '. SQL=' + @SQL;
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	
		exec (@SQL);

	end try
	begin catch;
		set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' creating Certificate: ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
	end catch;

	set @ChangesMade = @ChangesMade + 1;
end;


----------------------------------------------------------------------------------
-- for each user database matching our @DBNameSearch value, Create a database encryption key & enable TDE 


Declare DBnames_cursor cursor for
select name 
from master.dbo.sysdatabases 
where name not in('master', 'model', 'msdb','tempdb')
and name like isnull(@DBNameSearch, '%')
order by 1;

Open DBnames_cursor;

while 1 = 1
begin;
	fetch next from DBnames_cursor INTO @DBName;
	if @@fetch_status <> 0 break;
	set @DBCnt = @DBCnt + 1;

	set @strMsg = '- Processing database "' + @DBName + '"...';
	exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;


	----------------------------------------------------------------------------------
	--  Create the DEK if necessary...
	CreateDEK:

	select @State = encryption_state
	from master.sys.dm_database_encryption_keys 
	where db_name(database_id) = @DBName ;

	if @@rowcount = 0 or @State is null
		set @State = @STATE_NoEncryptionKey;

	-- if the database is currently undergoing an encryption state change, wait a bit then check again
	if @State in (@STATE_EncryptionInProgress, @STATE_DecryptionInProgress, @STATE_KeyChangeInProgress, @STATE_ProtectionChangeInProgress)
	begin;
		set @strMsg = '  - Database ' + @DBName + ' is currently undergoing an encryption state change (state=' + dbo.fnGetEncryptionStateDescription(@State) + '). Waiting...';
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
		waitfor delay @delayTime;
		goto CreateDEK;
	end;

	if @State = @STATE_Unencrypted or @State = @STATE_Encrypted
	begin;
		set @strMsg = '  - Database ' + @DBName + ' already has a DEK (state=' + dbo.fnGetEncryptionStateDescription(@State) + ') - do not need to create DEK.';
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	end;
	else if @State = @STATE_NoEncryptionKey
	begin;
		--The following code creates the DEK
		begin try;

			-- get the algorithm used for the SMK - we use the same for the DEK
			set @Algorithm = null;
			select @Algorithm = algorithm_desc
			from master.sys.symmetric_keys
			where name = '##MS_ServiceMasterKey##';

			if @@rowcount = 0 or @Algorithm is null
			begin;
				-- we didnt find a SMK for some reason - hard code it based on what we know about SQL 2008 and SQL 2012...
				if @@version like 'Microsoft SQL Server 2008%' 
					set @Algorithm = 'TRIPLE_DES_3KEY';
				else
					set @Algorithm = 'AES_256';
			end;

			if @Algorithm = 'TRIPLE_DES'
				set @Algorithm = 'TRIPLE_DES_3KEY';
			

			set @SQL = 'USE [' + @DBName + ']; '
						+ 'CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = ' + @Algorithm 					
							+ ' ENCRYPTION BY SERVER CERTifICATE [' + @CertName + ']'; 

			set @strMsg = '  - Creating DEK for Database: ' + @DBName  + ' (SQL=' + @SQL + ').';
			exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
			
			exec (@SQL);

		end try
		begin catch;
			set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' creating DEK for database ' + @DBName + ': ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
			exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
			close DBnames_cursor;
			deallocate DBnames_cursor;
			return 1;
		end catch;
	
	end;
	else
	begin;
		set @strMsg = 'ERROR: Unexpected database encryption state "' + isnull(convert(varchar(10),@State),'<null>') + '" (' + dbo.fnGetEncryptionStateDescription(@State) + ') for database ' + @DBName ;
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		close DBnames_cursor;
		deallocate DBnames_cursor;
		return 1;
	end;

	----------------------------------------------------------------------------------
	--  Enable encryption if necessary...
	EnableEncryption:

	select @State = encryption_state
	from master.sys.dm_database_encryption_keys 
	where db_name(database_id) = @DBName ;

	if @@rowcount = 0 or @State is null
		set @State = @STATE_NoEncryptionKey;

	-- if the database is currently undergoing an encryption state change, wait a bit then check again
	if @State in (@STATE_EncryptionInProgress, @STATE_DecryptionInProgress, @STATE_KeyChangeInProgress, @STATE_ProtectionChangeInProgress)
	begin;
		set @strMsg = '  - Database ' + @DBName + ' is currently undergoing an encryption state change (state=' + dbo.fnGetEncryptionStateDescription(@State) + '). Waiting...';
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
		waitfor delay @delayTime;
		goto EnableEncryption;
	end;

	if @State = @STATE_Encrypted
	begin;
		set @strMsg = '  - Database ' + @DBName + ' is already encrypted (state=' + dbo.fnGetEncryptionStateDescription(@State) + ') - do not need to encrypt.';
		exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	end;
	else if @State =  @STATE_Unencrypted 
	begin;
		--The following code encrypts the database
		begin try;

			set @SQL = 'ALTER DATABASE [' + @DBName + '] SET ENCRYPTION ON;';

			set @strMsg = '  - Encrypting Database: ' + @DBName  + ' (SQL=' + @SQL + ').';
			exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

			exec (@SQL);

		end try
		begin catch;
			set @strMsg =  'ERROR ' + isnull(convert(varchar(10),ERROR_NUMBER()),'<null>') + ' encrypting database ' + @DBName + ': ' + isnull(ERROR_MESSAGE(),'<null>') + ' SQL Statement was: ' + isnull(@SQL,'<null>');
			if ERROR_NUMBER() = 5069
				set @strMsg = @strMsg + '. This can occur when the database has changes from previous encryption scans that are pending log backup. Take a log backup and retry the command.'
			exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
			close DBnames_cursor;
			deallocate DBnames_cursor;
			return 1;
		end catch;
		
	end;
	else
	begin;
		set @strMsg = 'ERROR: Unexpected database encryption state "' + isnull(convert(varchar(10),@State),'<null>') + '" (' + dbo.fnGetEncryptionStateDescription(@State) + ') for database ' + @DBName ;
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		close DBnames_cursor;
		deallocate DBnames_cursor;
		return 1;
	end;

end;

close DBnames_cursor;
deallocate DBnames_cursor;

if @DBCnt = 0
begin;
	set @strMsg = 'ERROR: No user databases match name ''' + @DBNameSearch + '''.';
	exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
	return 1;
end;

set @strMsg =  '- TDE Configuration complete. Processed ' + isnull(convert(varchar(10),@DBCnt),'<null>') + ' databases.';
exec dbo.prcLogMessage @strMsg , @ProcName=@ProcName;



-- if we made anu changes at all, then call the proc to immediately backup all keys & certs
if @ChangesMade = 0
	exec dbo.prcLogMessage '- No SMK, DMK or Certificate changes made. Not calling Calling proc to backup all TDE keys & certificates.', @ProcName=@ProcName;
else
begin;
	--Take a Backup of all the keys
	exec dbo.prcLogMessage '- Calling proc to backup all TDE keys & certificates.', @ProcName=@ProcName;
	exec @rc = dbo.prcBackupTDEKeys;
	select @rc = isnull(@rc,0) + @@error;
	if @rc <> 0
	begin;
		set @strMsg = 'ERROR: Proc ''prcBackupTDEKeys'' terminated with RC=' + isnull(convert(varchar(10),@rc),'<null>') + '.';
		exec dbo.prcLogMessage @strMsg , 'Error', @ProcName=@ProcName;
		return 1;
	end;
end;

exec dbo.prcLogMessage '<LogProcEndMsg>', @ProcName=@ProcName;

go

-- ======================================================================================================================
set ANSI_NULLS ON;
set QUOTED_IDENTIFIER ON;
GO
if object_id('[dbo].[prcCreateKeyBackupJob]') is null
	exec ('create procedure [dbo].[prcCreateKeyBackupJob] as print ''Dummy proc.'' ');
go
alter procedure [dbo].[prcCreateKeyBackupJob]
(
	@Debug char(1) = 'N'
)
as
/************************************************************************************************
	Routine to create/update the SQL Agent job to backup keys/certificates

	

************************************************************************************************/

set nocount on;
Declare @strMsg				varchar(4000);
Declare @JobId				binary(16);
Declare @JobName			sysname			= N'YuvanDBA - TDE Keys Backup Job';
Declare @JobCategory		sysname			= N'TDE';
Declare @StepName1			sysname			= N'Backup the TDE Keys and certificate';
Declare @StepName2			sysname			= N'TDE Keys Backup - Failure';
Declare @OldStepName		sysname			= N'Backup the TDE Keys';
Declare @Command1			varchar(1000)	= N'exec TDEAdmin.dbo.prcBackupTDEKeys';
Declare @Command2			varchar(1000)	= N'RAISERROR (''DBS-AHD[4]: YuvanDBA - TDE Keys Backup Job - Keys backup failed'', 16, 1) with log';
Declare @ScheduleName		sysname			= N'TDE Keys Schedule';
Declare @rc					int				= 0;
Declare @StepId				int;
Declare @ProcName			sysname			= object_name(@@procid);
exec dbo.prcLogMessage '<LogProcStartMsg>', @ProcName=@ProcName;

-- check user is sysadmin
if isnull(is_srvrolemember('sysadmin'),-1) <> 1
begin;
	exec dbo.prcLogMessage 'ERROR: You must be a member of the sysadmin server role to run this routine.', 'Error', @ProcName=@ProcName;
	return 1;
end;


exec dbo.prcLogMessage '- Configuing SQL Agent job to backup TDE keys and certificates...', @ProcName=@ProcName;



BEGIN TRANSACTION ;

if not exists (select name from msdb.dbo.syscategories where name = @JobCategory AND category_class = 1) 
begin ;
	set @strMsg = '- Creating SQL Agent job category: ' + @JobCategory ;
	if @Debug = 'Y' exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	exec @rc = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=@JobCategory;
	if (@@ERROR <> 0 OR @rc <> 0) GOTO QuitWithRollback ;
end ;


----------------------------------------------------------------------------------------------
-- Create the job if necessary
 
--check if the Job already exists
select @JobId = job_id 
from msdb.dbo.sysjobs 
where name = @JobName ;

if (@JobId is not null)
begin ;
	set @strMsg = '- Job already exists: ' + @JobName;
	if @Debug = 'Y' exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	exec @rc =  msdb.dbo.sp_update_job @job_name=@JobName,  
			@enabled=1,
			@description=N'TDE Keys Backup Job',  
			@category_name=N'TDE',  
			@owner_login_name=N'sa';
	if (@@ERROR <> 0 OR @rc <> 0) GOTO QuitWithRollback ;
end;
else
begin;
	set @strMsg = '- Creating SQL Agent job: ' + @JobName;
	if @Debug = 'Y' exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

	exec @rc =  msdb.dbo.sp_add_job @job_name=@JobName,  
			@enabled=1,
			@description=N'TDE Keys Backup Job',  
			@category_name=N'TDE',  
			@owner_login_name=N'sa', @job_id = @JobId OUTPUT ;
	if (@@ERROR <> 0 OR @rc <> 0) GOTO QuitWithRollback ;
end;


----------------------------------------------------------------------------------------------
-- If the job step from the previous script version exists, delete it

select @StepId = step_id from msdb.dbo.sysjobsteps where job_id = @JobId and step_name = @OldStepName;
if @@rowcount > 0
begin;
	set @strMsg = '- Deleting old job step: ' + @OldStepName;
	if @Debug = 'Y' exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	exec @rc = msdb.dbo.sp_delete_jobstep @job_id=@JobId, @step_id=@StepId;
	if (@@ERROR <> 0 OR @rc <> 0) GOTO QuitWithRollback ;
end;


----------------------------------------------------------------------------------------------
-- Create job step 1 if necessary

select @StepId = step_id from msdb.dbo.sysjobsteps where job_id = @JobId and step_name = @StepName1;
if @@rowcount > 0
begin;
	set @strMsg = '- Updating SQL Agent job step: ' + @StepName1;
	if @Debug = 'Y' exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	exec @rc = msdb.dbo.sp_update_jobstep @job_id=@JobId, @step_id=@StepId,  
			@step_name=@StepName1,  
			@cmdexec_success_code=0,  
			@on_success_action=1,  
			@on_success_step_id=0,  
			@on_fail_action=3,  
			@on_fail_step_id=2,  
			@retry_attempts=0,  
			@retry_interval=0,  
			@os_run_priority=0, @subsystem=N'TSQL',  
			@command=@Command1,  
			@database_name=N'TDEAdmin',  
			@flags=0 ;
	if (@@ERROR <> 0 OR @rc <> 0) GOTO QuitWithRollback ;
end;
else
begin;
	set @strMsg = '- Creating SQL Agent job step: ' + @StepName1;
	if @Debug = 'Y' exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

	exec @rc = msdb.dbo.sp_add_jobstep @job_id=@JobId, @step_name=@StepName1,  
			@step_id=1,  
			@cmdexec_success_code=0,  
			@on_success_action=1,  
			@on_success_step_id=0,  
			@on_fail_action=3,  
			@on_fail_step_id=2,  
			@retry_attempts=0,  
			@retry_interval=0,  
			@os_run_priority=0, @subsystem=N'TSQL',  
			@command=@Command1,  
			@database_name=N'TDEAdmin',  
			@flags=0 ;
	if (@@ERROR <> 0 OR @rc <> 0) GOTO QuitWithRollback ;
end;

----------------------------------------------------------------------------------------------
-- Create job step 2 if necessary

select @StepId = step_id from msdb.dbo.sysjobsteps where job_id = @JobId and step_name = @StepName2;
if @@rowcount > 0
begin;

	set @strMsg = '- Updating SQL Agent job step: ' + @StepName2;
	if @Debug = 'Y' exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	exec @rc = msdb.dbo.sp_update_jobstep @job_id=@JobId, @step_id=@StepId,  
			@step_name=@StepName2,
			@cmdexec_success_code=0,  
			@on_success_action=2,  
			@on_success_step_id=0,  
			@on_fail_action=2,  
			@on_fail_step_id=0,  
			@retry_attempts=0,  
			@retry_interval=0,  
			@os_run_priority=0, @subsystem=N'TSQL',  
			@command=@Command2,  
			@database_name=N'master',  
			@flags=0 ;
	if (@@ERROR <> 0 OR @rc <> 0) GOTO QuitWithRollback ;
end;
else
begin;
	
	set @strMsg = '- Creating SQL Agent job step: ' + @StepName2;
	if @Debug = 'Y' exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

	exec @rc = msdb.dbo.sp_add_jobstep @job_id=@JobId, @step_name=@StepName2,
			@step_id=2,  
			@cmdexec_success_code=0,  
			@on_success_action=2,  
			@on_success_step_id=0,  
			@on_fail_action=2,  
			@on_fail_step_id=0,  
			@retry_attempts=0,  
			@retry_interval=0,  
			@os_run_priority=0, @subsystem=N'TSQL',  
			@command=@Command2,  
			@database_name=N'master',  
			@flags=0 ;
	if (@@ERROR <> 0 OR @rc <> 0) GOTO QuitWithRollback ;
end;


----------------------------------------------------------------------------------------------
-- Make sure the start step is 1

if exists (select 1 from msdb.dbo.sysjobs where job_id = @JobId and isnull(start_step_id,99) <> 1)
begin;
	set @strMsg = '- Setting job start step to 1'
	if @Debug = 'Y' exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	exec @rc = msdb.dbo.sp_update_job @job_id = @JobId, @start_step_id = 1 ;
	if (@@ERROR <> 0 OR @rc <> 0) GOTO QuitWithRollback ;
end;

----------------------------------------------------------------------------------------------
-- Create job schedule if necessary

if exists (select 1 
			from msdb.dbo.sysjobschedules js
			join msdb.dbo.sysschedules s
				on s.schedule_id = js.schedule_id
			where js.job_id = @JobId 
			  and s.name = @ScheduleName)
begin;
	set @strMsg = '- Updating job schedule'
	if @Debug = 'Y' exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	exec @rc = msdb.dbo.sp_update_jobschedule  @name=@ScheduleName, @job_name = @JobName,
			@enabled = 1,
			@freq_type = 8,			-- weekly
			@freq_recurrence_factor=2,	-- every second
			@freq_interval = 64,		-- Saturday
			@freq_subday_type=0x1,		-- at a specifiied time
			@active_start_time = 200500 ;	-- 8:05pm
	if (@@ERROR <> 0 OR @rc <> 0) GOTO QuitWithRollback;
end;
else
begin;
	
	set @strMsg = '- Creating SQL Agent job schedule: ' + @ScheduleName;
	if @Debug = 'Y' exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;

	exec @rc = msdb.dbo.sp_add_jobschedule  @name=@ScheduleName, @job_name = @JobName,
			@enabled = 1,
			@freq_type = 8,			-- weekly
			@freq_recurrence_factor=2,	-- every second
			@freq_interval = 64,		-- Saturday
			@freq_subday_type=0x1,		-- at a specifiied time
			@active_start_time = 200500 ;	-- 8:05pm
	if (@@ERROR <> 0 OR @rc <> 0) GOTO QuitWithRollback;
end;

if not exists (select 1 from msdb.dbo.sysjobservers where job_id = @JobId and server_id = 0)
begin;
	set @strMsg = '- Adding job server';
	if @Debug = 'Y' exec dbo.prcLogMessage @strMsg, @ProcName=@ProcName;
	exec @rc = msdb.dbo.sp_add_jobserver @job_id = @JobId, @server_name = N'(local)';
	if (@@ERROR <> 0 OR @rc <> 0) GOTO QuitWithRollback;
end;

COMMIT TRANSACTION ;
exec dbo.prcLogMessage '- SQL Agent job configuration is complete.', @ProcName=@ProcName;
GOTO EndSave ;

QuitWithRollback: 
    if (@@TRANCOUNT > 0) ROLLBACK TRANSACTION ;
	set @strMsg = 'ERROR: SQL Agent job configuration failed. Last step was: ' + @strMsg;
	exec dbo.prcLogMessage @strMsg, 'Error', @ProcName=@ProcName;
	return 1;
EndSave: 

exec dbo.prcLogMessage '<LogProcEndMsg>', @ProcName=@ProcName;

GO
use master;
go
--
-- ======================================================================================================================
-- 
--  All stored procedures etc are now created.  Now we encrypt the TDEAdmin database
--
set nocount on;
declare @rc				int;
Declare @strMsg			varchar(4000);
Declare @ScriptName		sysname = 'TDE Config Script';
exec TDEAdmin.dbo.prcLogMessage 'TDE Configuration script: TDEAdmin object Creation completed.', @ProcName=@ScriptName;
exec TDEAdmin.dbo.prcLogMessage 'TDE Configuration script: Calling proc to encrypt TDEAdmin database...', @ProcName=@ScriptName;

-- If we are in a known non-production domain, force the standard lab password...
if DEFAULT_DOMAIN() in (
			'GLOBALINFDEV', 'GLOBALTEST', 'ECORPTST', 'QAECORP',
			'APPDEV', 'OCEANIATST', 'OCEANIATST4', 'ECOMTST', 'QAECOM'
			)
	exec @rc = TDEAdmin.dbo.prcDeployTDE 'TDEAdmin', @SkipPasswordGeneration='Y', @Password='Ev*luti*n0456789';
else
	exec @rc = TDEAdmin.dbo.prcDeployTDE 'TDEAdmin';

set @rc = isnull(@rc,0) + @@error;
if @rc <> 0
begin;
	exec TDEAdmin.dbo.prcLogMessage 'ERROR: Encryption of the TDEAdmin database failed!', 'Error', @ProcName=@ScriptName;
end;
else
begin;
	-- Now create the job to backup keys etc...

	exec @rc = TDEAdmin.dbo.prcCreateKeyBackupJob;
	set @rc = isnull(@rc,0) + @@error;
	if @rc <> 0
	begin;
		exec TDEAdmin.dbo.prcLogMessage 'ERROR: Creation of key backup job failed!', 'Error', @ProcName=@ScriptName;
	end;
	else
	begin;

		exec TDEAdmin.dbo.prcLogMessage '', @ProcName=@ScriptName;
		exec TDEAdmin.dbo.prcLogMessage 'TDE Configuration is complete.', @ProcName=@ScriptName;
		exec TDEAdmin.dbo.prcLogMessage '', @ProcName=@ScriptName;
		exec TDEAdmin.dbo.prcLogMessage 'To encrypt a database, use one of the following commands:', @ProcName=@ScriptName;
		exec TDEAdmin.dbo.prcLogMessage '   exec TDEAdmin.dbo.prcDeployTDE ''<dbname>''		--  Encrypts one database', @ProcName=@ScriptName;
		exec TDEAdmin.dbo.prcLogMessage '   exec TDEAdmin.dbo.prcDeployTDE ''DB%''			--  Encrypts matching databases', @ProcName=@ScriptName;
		exec TDEAdmin.dbo.prcLogMessage '', @ProcName=@ScriptName;
		exec TDEAdmin.dbo.prcLogMessage 'To check the status of database encryption, use:', @ProcName=@ScriptName;
		exec TDEAdmin.dbo.prcLogMessage '   exec TDEAdmin.dbo.prcCheckTDE', @ProcName=@ScriptName;
		exec TDEAdmin.dbo.prcLogMessage '', @ProcName=@ScriptName;
	end;
end;
go
