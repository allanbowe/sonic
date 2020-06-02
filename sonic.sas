%let appLoc=/User Folders/&sysuserid/My Folder; 
%let syscc=0;
options ps=max noquotelenmax;
%macro mf_getattrn(
libds
,attr
)/*/STORE SOURCE*/;
%local dsid rc;
%let dsid=%sysfunc(open(&libds,is));
%if &dsid = 0 %then %do;
%put WARNING: Cannot open %trim(&libds), system message below;
%put %sysfunc(sysmsg());
-1
%end;
%else %do;
%sysfunc(attrn(&dsid,&attr))
%let rc=%sysfunc(close(&dsid));
%end;
%mend;
%macro mf_nobs(libds
)/*/STORE SOURCE*/;
%mf_getattrn(&libds,NLOBS)
%mend;
%macro mf_abort(mac=mf_abort.sas, type=, msg=, iftrue=%str(1=1)
)/*/STORE SOURCE*/;
%if not(%eval(%unquote(&iftrue))) %then %return;
%put NOTE: ///  mf_abort macro executing //;
%if %length(&mac)>0 %then %put NOTE- called by &mac;
%put NOTE - &msg;
/* Stored Process Server web app context */
%if %symexist(_metaperson) or "&SYSPROCESSNAME"="Compute Server" %then %do;
options obs=max replace nosyntaxcheck mprint;
/* extract log err / warn, if exist */
%local logloc logline;
%global logmsg; /* capture global messages */
%if %symexist(SYSPRINTTOLOG) %then %let logloc=&SYSPRINTTOLOG;
%else %let logloc=%qsysfunc(getoption(LOG));
proc printto log=log;run;
%if %length(&logloc)>0 %then %do;
%let logline=0;
data _null_;
infile &logloc lrecl=5000;
input; putlog _infile_;
i=1;
retain logonce 0;
if (_infile_=:"%str(WARN)ING" or _infile_=:"%str(ERR)OR") and logonce=0 then do;
call symputx('logline',_n_);
logonce+1;
end;
run;
/* capture log including lines BEFORE the err */
%if &logline>0 %then %do;
data _null_;
infile &logloc lrecl=5000;
input;
i=1;
stoploop=0;
if _n_ ge &logline-5 and stoploop=0 then do until (i>12);
call symputx('logmsg',catx('\n',symget('logmsg'),_infile_));
input;
i+1;
stoploop=1;
end;
if stoploop=1 then stop;
run;
%end;
%end;
/* send response in SASjs JSON format */
data _null_;
file _webout mod lrecl=32000;
length msg $32767;
sasdatetime=datetime();
msg=cats(symget('msg'),'\n\nLog Extract:\n',symget('logmsg'));
/* escape the quotes */
msg=tranwrd(msg,'"','\"');
/* ditch the CRLFs as chrome complains */
msg=compress(msg,,'kw');
/* quote without quoting the quotes (which are escaped instead) */
msg=cats('"',msg,'"');
if symexist('_debug') then debug=symget('_debug');
if debug ge 131 then put '>>weboutBEGIN<<';
put '{"START_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '"';
put ',"sasjsAbort" : [{';
put ' "MSG":' msg ;
put ' ,"MAC": "' "&mac" '"}]';
put ",""SYSUSERID"" : ""&sysuserid"" ";
if symexist('_metauser') then do;
_METAUSER=quote(trim(symget('_METAUSER')));
put ",""_METAUSER"": " _METAUSER;
_METAPERSON=quote(trim(symget('_METAPERSON')));
put ',"_METAPERSON": ' _METAPERSON;
end;
_PROGRAM=quote(trim(resolve(symget('_PROGRAM'))));
put ',"_PROGRAM" : ' _PROGRAM ;
put ",""SYSCC"" : ""&syscc"" ";
put ",""SYSERRORTEXT"" : ""&syserrortext"" ";
put ",""SYSJOBID"" : ""&sysjobid"" ";
put ",""SYSWARNINGTEXT"" : ""&syswarningtext"" ";
put ',"END_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '" ';
put "}" @;
%if &_debug ge 131 %then %do;
put '>>weboutEND<<';
%end;
run;
%let syscc=0;
%if %symexist(SYS_JES_JOB_URI) %then %do;
/* refer web service output to file service in one hit */
filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name="_webout.json";
%let rc=%sysfunc(fcopy(_web,_webout));
%end;
%else %do;
data _null_;
if symexist('sysprocessmode')
then if symget("sysprocessmode")="SAS Stored Process Server"
then rc=stpsrvset('program error', 0);
run;
%end;
%put _all_;
filename skip temp;
data _null_;
file skip;
put '%macro skip(); %macro skippy();';
run;
%inc skip;
%end;
%else %do;
%put _all_;
%abort cancel;
%end;
%mend;
%macro mf_verifymacvars(
verifyVars  /* list of macro variable NAMES */
,makeUpcase=NO  /* set to YES to make all the variable VALUES uppercase */
,mAbort=SOFT
)/*/STORE SOURCE*/;
%local verifyIterator verifyVar abortmsg;
%do verifyIterator=1 %to %sysfunc(countw(&verifyVars,%str( )));
%let verifyVar=%qscan(&verifyVars,&verifyIterator,%str( ));
%if not %symexist(&verifyvar) %then %do;
%let abortmsg= Variable &verifyVar is MISSING;
%goto exit_err;
%end;
%if %length(%trim(&&&verifyVar))=0 %then %do;
%let abortmsg= Variable &verifyVar is EMPTY;
%goto exit_err;
%end;
%if &makeupcase=YES %then %do;
%let &verifyVar=%upcase(&&&verifyvar);
%end;
%end;
%goto exit_success;
%exit_err:
%if &mAbort=SOFT %then %put %str(ERR)OR: &abortmsg;
%else %mf_abort(mac=mf_verifymacvars,type=&mabort,msg=&abortmsg);
%exit_success:
%mend;
%macro mm_getDirectories(
path=
,outds=work.mm_getDirectories
,mDebug=0
)/*/STORE SOURCE*/;
%local mD;
%if &mDebug=1 %then %let mD=;
%else %let mD=%str(*);
%&mD.put Executing mm_getDirectories.sas;
%&mD.put _local_;
data &outds (keep=directoryuri name directoryname directorydesc );
length directoryuri name directoryname directorydesc $256;
call missing(of _all_);
__i+1;
%if %length(&path)=0 %then %do;
do while
(metadata_getnobj("omsobj:Directory?@Id contains '.'",__i,directoryuri)>0);
%end; %else %do;
do while
(metadata_getnobj("omsobj:Directory?@DirectoryName='&path'",__i,directoryuri)>0);
%end;
__rc1=metadata_getattr(directoryuri, "Name", name);
__rc2=metadata_getattr(directoryuri, "DirectoryName", directoryname);
__rc3=metadata_getattr(directoryuri, "Desc", directorydesc);
&mD.putlog (_all_) (=);
drop __:;
__i+1;
if sum(of __rc1-__rc3)=0 then output;
end;
run;
%mend;
%macro mm_updatestpsourcecode(stp=
,stpcode=
,minify=NO
,frefin=inmeta
,frefout=outmeta
,mdebug=0
);
/* first, check if STP exists */
%local tsuri;
%let tsuri=stopifempty ;
data _null_;
format type uri tsuri value $200.;
call missing (of _all_);
path="&stp.(StoredProcess)";
/* first, find the STP ID */
if metadata_pathobj("",path,"StoredProcess",type,uri)>0 then do;
/* get sourcecode */
cnt=1;
do while (metadata_getnasn(uri,"Notes",cnt,tsuri)>0);
rc=metadata_getattr(tsuri,"Name",value);
put tsuri= value=;
if value="SourceCode" then do;
/* found it! */
rc=metadata_getattr(tsuri,"Id",value);
call symputx('tsuri',value,'l');
stop;
end;
cnt+1;
end;
end;
else put (_all_)(=);
run;
%if &tsuri=stopifempty %then %do;
%put WARNING:  &stp.(StoredProcess) not found!;
%return;
%end;
%if %length(&stpcode)<2 %then %do;
%put WARNING:  No SAS code supplied!!;
%return;
%end;
filename &frefin temp lrecl=32767;
/* write header XML */
data _null_;
file &frefin;
put "<UpdateMetadata><Reposid>$METAREPOSITORY</Reposid>
<Metadata><TextStore id='&tsuri' StoredText='";
run;
/* escape code so it can be stored as XML */
/* write contents */
%if %length(&stpcode)>2 %then %do;
data _null_;
file &frefin mod;
infile &stpcode lrecl=32767;
length outstr $32767;
input outstr ;
/* escape code so it can be stored as XML */
outstr=tranwrd(_infile_,'&','&amp;');
outstr=tranwrd(outstr,'<','&lt;');
outstr=tranwrd(outstr,'>','&gt;');
outstr=tranwrd(outstr,"'",'&apos;');
outstr=tranwrd(outstr,'"','&quot;');
outstr=tranwrd(outstr,'0A'x,'&#x0a;');
outstr=tranwrd(outstr,'0D'x,'&#x0d;');
outstr=tranwrd(outstr,'$','&#36;');
%if &minify=YES %then %do;
outstr=cats(outstr);
if outstr ne '';
if not (outstr=:'/*' and subpad(left(reverse(outstr)),1,2)='/*');
%end;
outstr=trim(outstr);
put outstr '&#10;';
run;
%end;
data _null_;
file &frefin mod;
put "'></TextStore></Metadata><NS>SAS</NS><Flags>268435456</Flags>
</UpdateMetadata>";
run;
filename &frefout temp;
proc metadata in= &frefin out=&frefout;
run;
%if &mdebug=1 %then %do;
/* write the response to the log for debugging */
data _null_;
infile &frefout lrecl=32767;
input;
put _infile_;
run;
%end;
%mend;
%macro mf_isblank(param
)/*/STORE SOURCE*/;
%sysevalf(%superq(param)=,boolean)
%mend;
%macro mp_dropmembers(
list /* space separated list of datasets / views */
,libref=WORK  /* can only drop from a single library at a time */
)/*/STORE SOURCE*/;
%if %mf_isblank(&list) %then %do;
%put NOTE: nothing to drop!;
%return;
%end;
proc datasets lib=&libref nolist;
delete &list;
delete &list /mtype=view;
run;
%mend;
%macro mm_getrepos(
outds=work.mm_getrepos
)/*/STORE SOURCE*/;
* use a temporary fileref to hold the response;
filename response temp;
/* get list of libraries */
proc metadata in=
"<GetRepositories><Repositories/><Flags>1</Flags><Options/></GetRepositories>"
out=response;
run;
/* write the response to the log for debugging */
/* create an XML map to read the response */
filename sxlemap temp;
data _null_;
file sxlemap;
put '<SXLEMAP version="1.2" name="SASRepos"><TABLE name="SASRepos">';
put "<TABLE-PATH syntax='XPath'>/GetRepositories/Repositories/Repository</TABLE-PATH>";
put '<COLUMN name="id">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@Id</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>200</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="name">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@Name</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>200</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="desc">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@Desc</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>200</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="DefaultNS">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@DefaultNS</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>200</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="RepositoryType">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@RepositoryType</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>20</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="RepositoryFormat">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@RepositoryFormat</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>10</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="Access">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@Access</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>16</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="CurrentAccess">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@CurrentAccess</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>16</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="PauseState">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@PauseState</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>16</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="Path">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@Path</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>256</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="Engine">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@Engine</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>8</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="Options">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@Options</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>32</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="MetadataCreated">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@MetadataCreated</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>24</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="MetadataUpdated">';
put "<PATH syntax='XPath'>/GetRepositories/Repositories/Repository/@MetadataUpdated</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>24</LENGTH>";
put '</COLUMN>';
put '</TABLE></SXLEMAP>';
run;
libname _XML_ xml xmlfileref=response xmlmap=sxlemap;
proc sort data= _XML_.SASRepos out=&outds;
by name;
run;
/* clear references */
filename sxlemap clear;
filename response clear;
libname _XML_ clear;
%mend;
%macro mm_getservercontexts(
outds=work.mm_getrepos
)/*/STORE SOURCE*/;
%local repo repocnt x;
%let repo=%sysfunc(getoption(metarepository));
/* first get list of available repos */
%mm_getrepos(outds=work.repos)
%let repocnt=0;
data _null_;
set repos;
where repositorytype in('CUSTOM','FOUNDATION');
keep id name ;
call symputx('repo'!!left(_n_),name,'l');
call symputx('repocnt',_n_,'l');
run;
filename __mc1 temp;
filename __mc2 temp;
data &outds; length serveruri servername $200; stop;run;
%do x=1 %to &repocnt;
options metarepository=&&repo&x;
proc metadata in=
"<GetMetadataObjects><Reposid>$METAREPOSITORY</Reposid>
<Type>ServerContext</Type><Objects/><NS>SAS</NS>
<Flags>0</Flags><Options/></GetMetadataObjects>"
out=__mc1;
run;
data _null_;
file __mc2;
put '<SXLEMAP version="1.2" name="SASContexts"><TABLE name="SASContexts">';
put "<TABLE-PATH syntax='XPath'>/GetMetadataObjects/Objects/ServerContext</TABLE-PATH>";
put '<COLUMN name="serveruri">';
put "<PATH syntax='XPath'>/GetMetadataObjects/Objects/ServerContext/@Id</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>200</LENGTH>";
put '</COLUMN>';
put '<COLUMN name="servername">';
put "<PATH syntax='XPath'>/GetMetadataObjects/Objects/ServerContext/@Name</PATH>";
put "<TYPE>character</TYPE><DATATYPE>string</DATATYPE><LENGTH>200</LENGTH>";
put '</COLUMN>';
put '</TABLE></SXLEMAP>';
run;
libname __mc3 xml xmlfileref=__mc1 xmlmap=__mc2;
proc append base=&outds data=__mc3.SASContexts;run;
libname __mc3 clear;
%end;
options metarepository=&repo;
filename __mc1 clear;
filename __mc2 clear;
%mend;
%macro mm_createstp(
stpname=Macro People STP
,stpdesc=This stp was created automatically by the mm_createstp macro
,filename=mm_createstp.sas
,directory=SASEnvironment/SASCode
,tree=/User Folders/sasdemo
,package=false
,streaming=true
,outds=work.mm_createstp
,mDebug=0
,server=SASApp
,stptype=1
,minify=NO
,frefin=mm_in
,frefout=mm_out
)/*/STORE SOURCE*/;
%local mD;
%if &mDebug=1 %then %let mD=;
%else %let mD=%str(*);
%&mD.put Executing mm_CreateSTP.sas;
%&mD.put _local_;
%mf_verifymacvars(stpname filename directory tree)
%mp_dropmembers(%scan(&outds,2,.))
data _null_;
length type uri $256;
rc=metadata_pathobj("","&tree","Folder",type,uri);
call symputx('foldertype',type,'l');
call symputx('treeuri',uri,'l');
run;
%if &foldertype ne Tree %then %do;
%put WARNING: Tree &tree does not exist!;
%return;
%end;
%local cmtype;
data _null_;
length type uri $256;
rc=metadata_pathobj("","&tree/&stpname",'StoredProcess',type,uri);
call symputx('cmtype',type,'l');
call symputx('stpuri',uri,'l');
run;
%if &cmtype = ClassifierMap %then %do;
%put WARNING: Stored Process &stpname already exists in &tree!;
%return;
%end;
%if %sysfunc(fileexist(&directory/&filename)) ne 1 %then %do;
%put WARNING: FILE *&directory/&filename* NOT FOUND!;
%return;
%end;
%if &stptype=1 %then %do;
/* type 1 STP - where code is stored on filesystem */
%if %sysevalf(&sysver lt 9.2) %then %do;
%put WARNING: Version 9.2 or later required;
%return;
%end;
/* check directory object (where 9.2 source code reference is stored) */
data _null_;
length id $20 dirtype $256;
rc=metadata_resolve("&directory",dirtype,id);
call symputx('checkdirtype',dirtype,'l');
run;
%if &checkdirtype ne Directory %then %do;
%mm_getdirectories(path=&directory,outds=&outds ,mDebug=&mDebug)
%if %mf_nobs(&outds)=0 or %sysfunc(exist(&outds))=0 %then %do;
%put WARNING: The directory object does not exist for &directory;
%return;
%end;
%end;
%else %do;
data &outds;
directoryuri="&directory";
run;
%end;
data &outds (keep=stpuri prompturi fileuri texturi);
length stpuri prompturi fileuri texturi serveruri $256 ;
set &outds;
/* final checks on uris */
length id $20 type $256;
__rc=metadata_resolve("&treeuri",type,id);
if type ne 'Tree' then do;
putlog "WARNING:  Invalid tree URI: &treeuri";
stopme=1;
end;
__rc=metadata_resolve(directoryuri,type,id);
if type ne 'Directory' then do;
putlog 'WARNING:  Invalid directory URI: ' directoryuri;
stopme=1;
end;
/* get server info */
__rc=metadata_resolve("&server",type,serveruri);
if type ne 'LogicalServer' then do;
__rc=metadata_getnobj("omsobj:LogicalServer?@Name='&server'",1,serveruri);
if serveruri='' then do;
putlog "WARNING:  Invalid server: &server";
stopme=1;
end;
end;
if stopme=1 then do;
putlog (_all_)(=);
stop;
end;
/* create empty prompt */
rc1=METADATA_NEWOBJ('PromptGroup',prompturi,'Parameters');
rc2=METADATA_SETATTR(prompturi, 'UsageVersion', '1000000');
rc3=METADATA_SETATTR(prompturi, 'GroupType','2');
rc4=METADATA_SETATTR(prompturi, 'Name','Parameters');
rc5=METADATA_SETATTR(prompturi, 'PublicType','Embedded:PromptGroup');
GroupInfo="<PromptGroup promptId='PromptGroup_%sysfunc(datetime())_&sysprocessid'"
!!" version='1.0'><Label><Text xml:lang='en-GB'>Parameters</Text>"
!!"</Label></PromptGroup>";
rc6 = METADATA_SETATTR(prompturi, 'GroupInfo',groupinfo);
if sum(of rc1-rc6) ne 0 then do;
putlog 'WARNING: Issue creating prompt.';
if prompturi ne . then do;
putlog '  Removing orphan: ' prompturi;
rc = METADATA_DELOBJ(prompturi);
put rc=;
end;
stop;
end;
/* create a file uri */
rc7=METADATA_NEWOBJ('File',fileuri,'SP Source File');
rc8=METADATA_SETATTR(fileuri, 'FileName',"&filename");
rc9=METADATA_SETATTR(fileuri, 'IsARelativeName','1');
rc10=METADATA_SETASSN(fileuri, 'Directories','MODIFY',directoryuri);
if sum(of rc7-rc10) ne 0 then do;
putlog 'WARNING: Issue creating file.';
if fileuri ne . then do;
putlog '  Removing orphans:' prompturi fileuri;
rc = METADATA_DELOBJ(prompturi);
rc = METADATA_DELOBJ(fileuri);
put (_all_)(=);
end;
stop;
end;
/* create a TextStore object */
rc11= METADATA_NEWOBJ('TextStore',texturi,'Stored Process');
rc12= METADATA_SETATTR(texturi, 'TextRole','StoredProcessConfiguration');
rc13= METADATA_SETATTR(texturi, 'TextType','XML');
storedtext='<?xml version="1.0" encoding="UTF-8"?><StoredProcess>'
!!"<ResultCapabilities Package='&package' Streaming='&streaming'/>"
!!"<OutputParameters/></StoredProcess>";
rc14= METADATA_SETATTR(texturi, 'StoredText',storedtext);
if sum(of rc11-rc14) ne 0 then do;
putlog 'WARNING: Issue creating TextStore.';
if texturi ne . then do;
putlog '  Removing orphans: ' prompturi fileuri texturi;
rc = METADATA_DELOBJ(prompturi);
rc = METADATA_DELOBJ(fileuri);
rc = METADATA_DELOBJ(texturi);
put (_all_)(=);
end;
stop;
end;
/* create meta obj */
rc15= METADATA_NEWOBJ('ClassifierMap',stpuri,"&stpname");
rc16= METADATA_SETASSN(stpuri, 'Trees','MODIFY',treeuri);
rc17= METADATA_SETASSN(stpuri, 'ComputeLocations','MODIFY',serveruri);
rc18= METADATA_SETASSN(stpuri, 'SourceCode','MODIFY',fileuri);
rc19= METADATA_SETASSN(stpuri, 'Prompts','MODIFY',prompturi);
rc20= METADATA_SETASSN(stpuri, 'Notes','MODIFY',texturi);
rc21= METADATA_SETATTR(stpuri, 'PublicType', 'StoredProcess');
rc22= METADATA_SETATTR(stpuri, 'TransformRole', 'StoredProcess');
rc23= METADATA_SETATTR(stpuri, 'UsageVersion', '1000000');
rc24= METADATA_SETATTR(stpuri, 'Desc', "&stpdesc");
/* tidy up if err */
if sum(of rc15-rc24) ne 0 then do;
putlog "%str(WARN)ING: Issue creating STP.";
if stpuri ne . then do;
putlog '  Removing orphans: ' prompturi fileuri texturi stpuri;
rc = METADATA_DELOBJ(prompturi);
rc = METADATA_DELOBJ(fileuri);
rc = METADATA_DELOBJ(texturi);
rc = METADATA_DELOBJ(stpuri);
put (_all_)(=);
end;
end;
else do;
fullpath=cats('_program=',treepath,"/&stpname");
putlog "NOTE: Stored Process Created!";
putlog "NOTE- "; putlog "NOTE-"; putlog "NOTE-" fullpath;
putlog "NOTE- "; putlog "NOTE-";
end;
output;
stop;
run;
%end;
%else %if &stptype=2 %then %do;
/* type 2 stp - code is stored in metadata */
%if %sysevalf(&sysver lt 9.3) %then %do;
%put WARNING: SAS version 9.3 or later required to create type2 STPs;
%return;
%end;
/* check we have the correct ServerContext */
%mm_getservercontexts(outds=contexts)
%local serveruri; %let serveruri=NOTFOUND;
data _null_;
set contexts;
where upcase(servername)="%upcase(&server)";
call symputx('serveruri',serveruri);
run;
%if &serveruri=NOTFOUND %then %do;
%put WARNING: ServerContext *&server* not found!;
%return;
%end;
filename &frefin temp;
data _null_;
file &frefin;
treeuri=quote(symget('treeuri'));
serveruri=quote(symget('serveruri'));
stpdesc=quote(symget('stpdesc'));
stpname=quote(symget('stpname'));
put "<AddMetadata><Reposid>$METAREPOSITORY</Reposid><Metadata> "/
'<ClassifierMap UsageVersion="2000000" IsHidden="0" IsUserDefined="0" '/
' IsActive="1" PublicType="StoredProcess" TransformRole="StoredProcess" '/
'  Name=' stpname ' Desc=' stpdesc '>'/
"  <ComputeLocations>"/
"    <ServerContext ObjRef=" serveruri "/>"/
"  </ComputeLocations>"/
"<Notes> "/
'  <TextStore IsHidden="0"  Name="SourceCode" UsageVersion="0" '/
'    TextRole="StoredProcessSourceCode" StoredText="%put hello world!;" />'/
'  <TextStore IsHidden="0" Name="Stored Process" UsageVersion="0" '/
'    TextRole="StoredProcessConfiguration" TextType="XML" '/
'    StoredText="&lt;?xml version=&quot;1.0&quot; encoding=&quot;UTF-8&qu'@@
'ot;?&gt;&lt;StoredProcess&gt;&lt;ServerContext LogicalServerType=&quot;S'@@
'ps&quot; OtherAllowed=&quot;false&quot;/&gt;&lt;ResultCapabilities Packa'@@
'ge=&quot;' @@ "&package" @@ '&quot; Streaming=&quot;' @@ "&streaming" @@
'&quot;/&gt;&lt;OutputParameters/&gt;&lt;/StoredProcess&gt;" />' /
"  </Notes> "/
"  <Prompts> "/
'   <PromptGroup  Name="Parameters" GroupType="2" IsHidden="0" '/
'     PublicType="Embedded:PromptGroup" UsageVersion="1000000" '/
'     GroupInfo="&lt;PromptGroup promptId=&quot;PromptGroup_1502797359253'@@
'_802080&quot; version=&quot;1.0&quot;&gt;&lt;Label&gt;&lt;Text xml:lang='@@
'&quot;en-US&quot;&gt;Parameters&lt;/Text&gt;&lt;/Label&gt;&lt;/PromptGro'@@
'up&gt;" />'/
"  </Prompts> "/
"<Trees><Tree ObjRef=" treeuri "/></Trees>"/
"</ClassifierMap></Metadata><NS>SAS</NS>"/
"<Flags>268435456</Flags></AddMetadata>";
run;
filename &frefout temp;
proc metadata in= &frefin out=&frefout ;
run;
%if &mdebug=1 %then %do;
/* write the response to the log for debugging */
data _null_;
infile &frefout lrecl=1048576;
input;
put _infile_;
run;
%end;
%mm_updatestpsourcecode(stp=&tree/&stpname
,stpcode="&directory/&filename"
,frefin=&frefin.
,frefout=&frefout.
,mdebug=&mdebug
,minify=&minify)
%end;
%else %do;
%put WARNING:  STPTYPE=*&stptype* not recognised!;
%end;
%mend;
%macro mf_getuser(type=META
)/*/STORE SOURCE*/;
%local user metavar;
%if &type=OS %then %let metavar=_secureusername;
%else %let metavar=_metaperson;
%if %symexist(SYS_COMPUTE_SESSION_OWNER) %then %let user=&SYS_COMPUTE_SESSION_OWNER;
%else %if %symexist(&metavar) %then %do;
%if %length(&&&metavar)=0 %then %let user=&sysuserid;
/* sometimes SAS will add @domain extension - remove for consistency */
%else %let user=%scan(&&&metavar,1,@);
%end;
%else %let user=&sysuserid;
%quote(&user)
%mend;
%macro mm_createfolder(path=,mDebug=0);
%put &sysmacroname: execution started for &path;
%local dbg errorcheck;
%if &mDebug=0 %then %let dbg=*;
%local parentFolderObjId child errorcheck paths;
%let paths=0;
%let errorcheck=1;
%if &syscc ge 4 %then %do;
%put SYSCC=&syscc - this macro requires a clean session;
%return;
%end;
data _null_;
length objId parentId objType parent child $200
folderPath $1000;
call missing (of _all_);
folderPath = "%trim(&path)";
* remove any trailing slash ;
if ( substr(folderPath,length(folderPath),1) = '/' ) then
folderPath=substr(folderPath,1,length(folderPath)-1);
* name must not be blank;
if ( folderPath = '' ) then do;
put "%str(ERR)OR: &sysmacroname PATH parameter value must be non-blank";
end;
* must have a starting slash ;
if ( substr(folderPath,1,1) ne '/' ) then do;
put "%str(ERR)OR: &sysmacroname PATH parameter value must have starting slash";
stop;
end;
* check if folder already exists ;
rc=metadata_pathobj('',cats(folderPath,"(Folder)"),"",objType,objId);
if rc ge 1 then do;
put "NOTE: Folder " folderPath " already exists!";
stop;
end;
* do not create a root (one level) folder ;
if countc(folderPath,'/')=1 then do;
put "%str(ERR)OR: &sysmacroname will not create a new ROOT folder";
stop;
end;
* check that root folder exists ;
root=cats('/',scan(folderpath,1,'/'),"(Folder)");
if metadata_pathobj('',root,"",objType,parentId)<1 then do;
put "%str(ERR)OR: " root " does not exist!";
stop;
end;
* check that parent folder exists ;
child=scan(folderPath,-1,'/');
parent=substr(folderpath,1,length(folderpath)-length(child)-1);
rc=metadata_pathobj('',cats(parent,"(Folder)"),"",objType,parentId);
if rc<1 then do;
putlog 'The following folders will be created:';
/* folder does not exist - so start from top and work down */
length newpath $1000;
paths=0;
do x=2 to countw(folderpath,'/');
newpath='';
do i=1 to x;
newpath=cats(newpath,'/',scan(folderpath,i,'/'));
end;
rc=metadata_pathobj('',cats(newpath,"(Folder)"),"",objType,parentId);
if rc<1 then do;
paths+1;
call symputx(cats('path',paths),newpath);
putlog newpath;
end;
call symputx('paths',paths);
end;
end;
else putlog "parent " parent " exists";
call symputx('parentFolderObjId',parentId,'l');
call symputx('child',child,'l');
call symputx('errorcheck',0,'l');
&dbg put (_all_)(=);
run;
%if &errorcheck=1 or &syscc ge 4 %then %return;
%if &paths>0 %then %do x=1 %to &paths;
%put executing recursive call for &&path&x;
%mm_createfolder(path=&&path&x)
%end;
%else %do;
filename __newdir temp;
options noquotelenmax;
%local inmeta;
%put creating: &path;
%let inmeta=<AddMetadata><Reposid>$METAREPOSITORY</Reposid><Metadata>
<Tree Name='&child' PublicType='Folder' TreeType='BIP Folder' UsageVersion='1000000'>
<ParentTree><Tree ObjRef='&parentFolderObjId'/></ParentTree></Tree></Metadata>
<NS>SAS</NS><Flags>268435456</Flags></AddMetadata>;
proc metadata in="&inmeta" out=__newdir verbose;
run ;
/* check it was successful */
data _null_;
length objId parentId objType parent child $200 ;
call missing (of _all_);
rc=metadata_pathobj('',cats("&path","(Folder)"),"",objType,objId);
if rc ge 1 then do;
putlog "SUCCCESS!  &path created.";
end;
else do;
putlog "%str(ERR)OR: unsuccessful attempt to create &path";
call symputx('syscc',8);
end;
run;
/* write the response to the log for debugging */
%if &mDebug ne 0 %then %do;
data _null_;
infile __newdir lrecl=32767;
input;
put _infile_;
run;
%end;
filename __newdir clear;
%end;
%put &sysmacroname: execution finished for &path;
%mend;
%macro mm_deletestp(
target=
)/*/STORE SOURCE*/;
%local cmtype;
data _null_;
length type uri $256;
rc=metadata_pathobj("","&target",'StoredProcess',type,uri);
call symputx('cmtype',type,'l');
call symputx('stpuri',uri,'l');
run;
%if &cmtype ne ClassifierMap %then %do;
%put NOTE: No Stored Process found at &target;
%return;
%end;
filename __in temp lrecl=10000;
filename __out temp lrecl=10000;
data _null_ ;
file __in ;
put "<DeleteMetadata><Metadata><ClassifierMap Id='&stpuri'/>";
put "</Metadata><NS>SAS</NS><Flags>268436480</Flags><Options/>";
put "</DeleteMetadata>";
run ;
proc metadata in=__in out=__out verbose;run;
/* list the result */
data _null_;infile __out; input; list; run;
filename __in clear;
filename __out clear;
%local isgone;
data _null_;
length type uri $256;
call missing (of _all_);
rc=metadata_pathobj("","&target",'Note',type,uri);
call symputx('isgone',type,'l');
run;
%if &isgone = ClassifierMap %then %do;
%put %str(ERR)OR: STP not deleted from &target;
%let syscc=4;
%return;
%end;
%mend;
%macro mm_createwebservice(path=
,name=initService
,precode=
,code=
,desc=This stp was created automagically by the mm_createwebservice macro
,mDebug=0
,server=SASApp
,replace=NO
,adapter=sasjs
)/*/STORE SOURCE*/;
%if &syscc ge 4 %then %do;
%put &=syscc - &sysmacroname will not execute in this state;
%return;
%end;
%local mD;
%if &mDebug=1 %then %let mD=;
%else %let mD=%str(*);
%&mD.put Executing mm_createwebservice.sas;
%&mD.put _local_;
* remove any trailing slash ;
%if "%substr(&path,%length(&path),1)" = "/" %then
%let path=%substr(&path,1,%length(&path)-1);
filename sasjs temp;
data _null_;
file sasjs lrecl=3000 ;
put "/* Created on %sysfunc(datetime(),datetime19.) by %mf_getuser() */";
/* WEBOUT BEGIN */
put ' ';
put '%macro mp_jsonout(action,ds,jref=_webout,dslabel=,fmt=Y,engine=PROCJSON,dbg=0 ';
put ')/*/STORE SOURCE*/; ';
put '%put output location=&jref; ';
put '%if &action=OPEN %then %do; ';
put '  data _null_;file &jref encoding=''utf-8''; ';
put '    put ''{"START_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''"''; ';
put '  run; ';
put '%end; ';
put '%else %if (&action=ARR or &action=OBJ) %then %do; ';
put '  options validvarname=upcase; ';
put '  data _null_;file &jref mod encoding=''utf-8''; ';
put '    put ", ""%lowcase(%sysfunc(coalescec(&dslabel,&ds)))"":"; ';
put ' ';
put '  %if &engine=PROCJSON %then %do; ';
put '    data;run;%let tempds=&syslast; ';
put '    proc sql;drop table &tempds; ';
put '    data &tempds /view=&tempds;set &ds; ';
put '    %if &fmt=N %then format _numeric_ best32.;; ';
put '    proc json out=&jref ';
put '        %if &action=ARR %then nokeys ; ';
put '        %if &dbg ge 131  %then pretty ; ';
put '        ;export &tempds / nosastags fmtnumeric; ';
put '    run; ';
put '    proc sql;drop view &tempds; ';
put '  %end; ';
put '  %else %if &engine=DATASTEP %then %do; ';
put '    %local cols i tempds; ';
put '    %let cols=0; ';
put '    %if %sysfunc(exist(&ds)) ne 1 & %sysfunc(exist(&ds,VIEW)) ne 1 %then %do; ';
put '      %put &sysmacroname:  &ds NOT FOUND!!!; ';
put '      %return; ';
put '    %end; ';
put '    data _null_;file &jref mod ; ';
put '      put "["; call symputx(''cols'',0,''l''); ';
put '    proc sort data=sashelp.vcolumn(where=(libname=''WORK'' & memname="%upcase(&ds)")) ';
put '      out=_data_; ';
put '      by varnum; ';
put ' ';
put '    data _null_; ';
put '      set _last_ end=last; ';
put '      call symputx(cats(''name'',_n_),name,''l''); ';
put '      call symputx(cats(''type'',_n_),type,''l''); ';
put '      call symputx(cats(''len'',_n_),length,''l''); ';
put '      if last then call symputx(''cols'',_n_,''l''); ';
put '    run; ';
put ' ';
put '    proc format; /* credit yabwon for special null removal */ ';
put '      value bart ._ - .z = null ';
put '      other = [best.]; ';
put ' ';
put '    data;run; %let tempds=&syslast; /* temp table for spesh char management */ ';
put '    proc sql; drop table &tempds; ';
put '    data &tempds/view=&tempds; ';
put '      attrib _all_ label=''''; ';
put '      %do i=1 %to &cols; ';
put '        %if &&type&i=char %then %do; ';
put '          length &&name&i $32767; ';
put '          format &&name&i $32767.; ';
put '        %end; ';
put '      %end; ';
put '      set &ds; ';
put '      format _numeric_ bart.; ';
put '    %do i=1 %to &cols; ';
put '      %if &&type&i=char %then %do; ';
put '        &&name&i=''"''!!trim(prxchange(''s/"/\"/'',-1, ';
put '                    prxchange(''s/''!!''0A''x!!''/\n/'',-1, ';
put '                    prxchange(''s/''!!''0D''x!!''/\r/'',-1, ';
put '                    prxchange(''s/''!!''09''x!!''/\t/'',-1, ';
put '                    prxchange(''s/\\/\\\\/'',-1,&&name&i) ';
put '        )))))!!''"''; ';
put '      %end; ';
put '    %end; ';
put '    run; ';
put '    /* write to temp loc to avoid _webout truncation - https://support.sas.com/kb/49/325.html */ ';
put '    filename _sjs temp lrecl=131068 encoding=''utf-8''; ';
put '    data _null_; file _sjs lrecl=131068 encoding=''utf-8'' mod; ';
put '      set &tempds; ';
put '      if _n_>1 then put "," @; put ';
put '      %if &action=ARR %then "[" ; %else "{" ; ';
put '      %do i=1 %to &cols; ';
put '        %if &i>1 %then  "," ; ';
put '        %if &action=OBJ %then """&&name&i"":" ; ';
put '        &&name&i ';
put '      %end; ';
put '      %if &action=ARR %then "]" ; %else "}" ; ; ';
put '    proc sql; ';
put '    drop view &tempds; ';
put '    /* now write the long strings to _webout 1 byte at a time */ ';
put '    data _null_; ';
put '      length filein 8 fileid 8; ';
put '      filein = fopen("_sjs",''I'',1,''B''); ';
put '      fileid = fopen("&jref",''A'',1,''B''); ';
put '      rec = ''20''x; ';
put '      do while(fread(filein)=0); ';
put '        rc = fget(filein,rec,1); ';
put '        rc = fput(fileid, rec); ';
put '        rc =fwrite(fileid); ';
put '      end; ';
put '      rc = fclose(filein); ';
put '      rc = fclose(fileid); ';
put '    run; ';
put '    filename _sjs clear; ';
put '    data _null_; file &jref mod encoding=''utf-8''; ';
put '      put "]"; ';
put '    run; ';
put '  %end; ';
put '%end; ';
put ' ';
put '%else %if &action=CLOSE %then %do; ';
put '  data _null_;file &jref encoding=''utf-8''; ';
put '    put "}"; ';
put '  run; ';
put '%end; ';
put '%mend; ';
put '%macro mm_webout(action,ds,dslabel=,fref=_webout,fmt=Y); ';
put '%global _webin_file_count _webin_fileref1 _webin_name1 _program _debug; ';
put '%local i tempds; ';
put ' ';
put '%if &action=FETCH %then %do; ';
put '  %if %str(&_debug) ge 131 %then %do; ';
put '    options mprint notes mprintnest; ';
put '  %end; ';
put '  %let _webin_file_count=%eval(&_webin_file_count+0); ';
put '  /* now read in the data */ ';
put '  %do i=1 %to &_webin_file_count; ';
put '    %if &_webin_file_count=1 %then %do; ';
put '      %let _webin_fileref1=&_webin_fileref; ';
put '      %let _webin_name1=&_webin_name; ';
put '    %end; ';
put '    data _null_; ';
put '      infile &&_webin_fileref&i termstr=crlf; ';
put '      input; ';
put '      call symputx(''input_statement'',_infile_); ';
put '      putlog "&&_webin_name&i input statement: "  _infile_; ';
put '      stop; ';
put '    data &&_webin_name&i; ';
put '      infile &&_webin_fileref&i firstobs=2 dsd termstr=crlf encoding=''utf-8''; ';
put '      input &input_statement; ';
put '      %if %str(&_debug) ge 131 %then %do; ';
put '        if _n_<20 then putlog _infile_; ';
put '      %end; ';
put '    run; ';
put '  %end; ';
put '%end; ';
put ' ';
put '%else %if &action=OPEN %then %do; ';
put '  /* fix encoding */ ';
put '  OPTIONS NOBOMFILE; ';
put '  data _null_; ';
put '    rc = stpsrv_header(''Content-type'',"text/html; encoding=utf-8"); ';
put '  run; ';
put ' ';
put '  /* setup json */ ';
put '  data _null_;file &fref encoding=''utf-8''; ';
put '  %if %str(&_debug) ge 131 %then %do; ';
put '    put ''>>weboutBEGIN<<''; ';
put '  %end; ';
put '    put ''{"START_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''"''; ';
put '  run; ';
put ' ';
put '%end; ';
put ' ';
put '%else %if &action=ARR or &action=OBJ %then %do; ';
put '  %if &sysver=9.4 %then %do; ';
put '    %mp_jsonout(&action,&ds,dslabel=&dslabel,fmt=&fmt ';
put '      ,engine=PROCJSON,dbg=%str(&_debug) ';
put '    ) ';
put '  %end; ';
put '  %else %do; ';
put '    %mp_jsonout(&action,&ds,dslabel=&dslabel,fmt=&fmt ';
put '      ,engine=DATASTEP,dbg=%str(&_debug) ';
put '    ) ';
put '  %end; ';
put '%end; ';
put '%else %if &action=CLOSE %then %do; ';
put '  %if %str(&_debug) ge 131 %then %do; ';
put '    /* if debug mode, send back first 10 records of each work table also */ ';
put '    options obs=10; ';
put '    data;run;%let tempds=%scan(&syslast,2,.); ';
put '    ods output Members=&tempds; ';
put '    proc datasets library=WORK memtype=data; ';
put '    %local wtcnt;%let wtcnt=0; ';
put '    data _null_; ';
put '      set &tempds; ';
put '      if not (name =:"DATA"); ';
put '      i+1; ';
put '      call symputx(''wt''!!left(i),name,''l''); ';
put '      call symputx(''wtcnt'',i,''l''); ';
put '    data _null_; file &fref encoding=''utf-8''; ';
put '      put ",""WORK"":{"; ';
put '    %do i=1 %to &wtcnt; ';
put '      %let wt=&&wt&i; ';
put '      proc contents noprint data=&wt ';
put '        out=_data_ (keep=name type length format:); ';
put '      run;%let tempds=%scan(&syslast,2,.); ';
put '      data _null_; file &fref encoding=''utf-8''; ';
put '        dsid=open("WORK.&wt",''is''); ';
put '        nlobs=attrn(dsid,''NLOBS''); ';
put '        nvars=attrn(dsid,''NVARS''); ';
put '        rc=close(dsid); ';
put '        if &i>1 then put '',''@; ';
put '        put " ""&wt"" : {"; ';
put '        put ''"nlobs":'' nlobs; ';
put '        put '',"nvars":'' nvars; ';
put '      %mp_jsonout(OBJ,&tempds,jref=&fref,dslabel=colattrs,engine=DATASTEP) ';
put '      %mp_jsonout(OBJ,&wt,jref=&fref,dslabel=first10rows,engine=DATASTEP) ';
put '      data _null_; file &fref encoding=''utf-8''; ';
put '        put "}"; ';
put '    %end; ';
put '    data _null_; file &fref encoding=''utf-8''; ';
put '      put "}"; ';
put '    run; ';
put '  %end; ';
put '  /* close off json */ ';
put '  data _null_;file &fref mod encoding=''utf-8''; ';
put '    _PROGRAM=quote(trim(resolve(symget(''_PROGRAM'')))); ';
put '    put ",""SYSUSERID"" : ""&sysuserid"" "; ';
put '    put ",""MF_GETUSER"" : ""%mf_getuser()"" "; ';
put '    put ",""_DEBUG"" : ""&_debug"" "; ';
put '    _METAUSER=quote(trim(symget(''_METAUSER''))); ';
put '    put ",""_METAUSER"": " _METAUSER; ';
put '    _METAPERSON=quote(trim(symget(''_METAPERSON''))); ';
put '    put '',"_METAPERSON": '' _METAPERSON; ';
put '    put '',"_PROGRAM" : '' _PROGRAM ; ';
put '    put ",""SYSCC"" : ""&syscc"" "; ';
put '    put ",""SYSERRORTEXT"" : ""&syserrortext"" "; ';
put '    put ",""SYSHOSTNAME"" : ""&syshostname"" "; ';
put '    put ",""SYSJOBID"" : ""&sysjobid"" "; ';
put '    put ",""SYSSITE"" : ""&syssite"" "; ';
put '    put ",""SYSWARNINGTEXT"" : ""&syswarningtext"" "; ';
put '    put '',"END_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''" ''; ';
put '    put "}" @; ';
put '  %if %str(&_debug) ge 131 %then %do; ';
put '    put ''>>weboutEND<<''; ';
put '  %end; ';
put '  run; ';
put '%end; ';
put ' ';
put '%mend; ';
put ' ';
put '%macro mf_getuser(type=META ';
put ')/*/STORE SOURCE*/; ';
put '  %local user metavar; ';
put '  %if &type=OS %then %let metavar=_secureusername; ';
put '  %else %let metavar=_metaperson; ';
put ' ';
put '  %if %symexist(SYS_COMPUTE_SESSION_OWNER) %then %let user=&SYS_COMPUTE_SESSION_OWNER; ';
put '  %else %if %symexist(&metavar) %then %do; ';
put '    %if %length(&&&metavar)=0 %then %let user=&sysuserid; ';
put '    /* sometimes SAS will add @domain extension - remove for consistency */ ';
put '    %else %let user=%scan(&&&metavar,1,@); ';
put '  %end; ';
put '  %else %let user=&sysuserid; ';
put ' ';
put '  %quote(&user) ';
put ' ';
put '%mend; ';
/* WEBOUT END */
put '%macro webout(action,ds,dslabel=,fmt=);';
put '  %mm_webout(&action,ds=&ds,dslabel=&dslabel,fmt=&fmt)';
put '%mend;';
run;
/* add precode and code */
%local work tmpfile;
%let work=%sysfunc(pathname(work));
%let tmpfile=__mm_createwebservice.temp;
%local x fref freflist mod;
%let freflist= &adapter &precode &code ;
%do x=1 %to %sysfunc(countw(&freflist));
%if &x>1 %then %let mod=mod;
%let fref=%scan(&freflist,&x);
%put &sysmacroname: adding &fref;
data _null_;
file "&work/&tmpfile" lrecl=3000 &mod;
infile &fref;
input;
put _infile_;
run;
%end;
/* create the metadata folder if not already there */
%mm_createfolder(path=&path)
%if &syscc ge 4 %then %return;
%if %upcase(&replace)=YES %then %do;
%mm_deletestp(target=&path/&name)
%end;
/* create the web service */
%mm_createstp(stpname=&name
,filename=&tmpfile
,directory=&work
,tree=&path
,stpdesc=&desc
,mDebug=&mdebug
,server=&server
,stptype=2)
/* find the web app url */
%local url;
%let url=localhost/SASStoredProcess;
data _null_;
length url $128;
rc=METADATA_GETURI("Stored Process Web App",url);
if rc=0 then call symputx('url',url,'l');
run;
%put ;%put ;%put ;%put ;%put ;%put ;
%put &sysmacroname: STP &name successfully created in &path;
%put ;%put ;%put ;
%put Check it out here:;
%put ;%put ;%put ;
%put &url?_PROGRAM=&path/&name;
%put ;%put ;%put ;%put ;%put ;%put ;
%mend;
%let path=;
%let service=clickme;
filename sascode temp lrecl=32767;
data _null_;
file sascode;
put '%macro sasjsout(type,fref=sasjs);';
put '%global sysprocessmode SYS_JES_JOB_URI;';
put '%if "&sysprocessmode"="SAS Compute Server" %then %do;';
put '%if &type=HTML %then %do;';
put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name="_webout.json"';
put 'contenttype="text/html";';
put '%end;';
put '%else %if &type=JS %then %do;';
put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.js''';
put 'contenttype=''application/javascript'';';
put '%end;';
put '%else %if &type=CSS %then %do;';
put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.css''';
put 'contenttype=''text/css'';';
put '%end;';
put '%else %if &type=PNG %then %do;';
put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.png''';
put 'contenttype=''image/png'' lrecl=2000000 recfm=n;';
put '%end;';
put '%else %if &type=MP3 %then %do;';
put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.mp3''';
put 'contenttype=''audio/mpeg'' lrecl=2000000 recfm=n;';
put '%end;';
put '%end;';
put '%else %do;';
put '%if &type=JS %then %do;';
put '%let rc=%sysfunc(stpsrv_header(Content-type,application/javascript));';
put '%end;';
put '%else %if &type=CSS %then %do;';
put '%let rc=%sysfunc(stpsrv_header(Content-type,text/css));';
put '%end;';
put '%else %if &type=PNG %then %do;';
put '%let rc=%sysfunc(stpsrv_header(Content-type,image/png));';
put '%end;';
put '%else %if &type=MP3 %then %do;';
put '%let rc=%sysfunc(stpsrv_header(Content-type,audio/mpeg));';
put '%end;';
put '%end;';
put '%if &type=HTML %then %do;';
put 'filename _sjs temp;';
put 'data _null_;';
put 'file _sjs lrecl=32767 encoding=''utf-8'';';
put 'infile &fref lrecl=32767;';
put 'input;';
put 'if find(_infile_,'' appLoc: '') then do;';
put 'pgm="&_program";';
put 'rootlen=length(trim(pgm))-length(scan(pgm,-1,''/''))-1;';
put 'root=quote(substr(pgm,1,rootlen));';
put 'put ''    appLoc: '' root '','';';
put 'end;';
put 'else if find(_infile_,'' serverType: '') then do;';
put 'if symexist(''_metaperson'') then put ''    serverType: "SAS9" ,'';';
put 'else put ''    serverType: "SASVIYA" ,'';';
put 'end;';
put 'else if find(_infile_,'' hostUrl: '') then do;';
put '/* nothing - we are streaming so this will default to hostname */';
put 'end;';
put 'else put _infile_;';
put 'run;';
put '%let fref=_sjs;';
put '%end;';
put '/* stream byte by byte */';
put '%if &type=PNG or &type=MP3 %then %do;';
put 'data _null_;';
put 'length filein 8 fileout 8;';
put 'filein = fopen("&fref",''I'',4,''B'');';
put 'fileout = fopen("_webout",''A'',1,''B'');';
put 'char= ''20''x;';
put 'do while(fread(filein)=0);';
put 'raw="1234";';
put 'do i=1 to 4;';
put 'rc=fget(filein,char,1);';
put 'substr(raw,i,1)=char;';
put 'end;';
put 'val="123";';
put 'val=input(raw,$base64X4.);';
put 'do i=1 to 3;';
put 'length byte $1;';
put 'byte=byte(rank(substr(val,i,1)));';
put 'rc = fput(fileout, byte);';
put 'end;';
put 'rc =fwrite(fileout);';
put 'end;';
put 'rc = fclose(filein);';
put 'rc = fclose(fileout);';
put 'run;';
put '%end;';
put '%else %do;';
put 'data _null_;';
put 'length filein 8 fileid 8;';
put 'filein = fopen("&fref",''I'',1,''B'');';
put 'fileid = fopen("_webout",''A'',1,''B'');';
put 'rec = ''20''x;';
put 'do while(fread(filein)=0);';
put 'rc = fget(filein,rec,1);';
put 'rc = fput(fileid, rec);';
put 'rc =fwrite(fileid);';
put 'end;';
put 'rc = fclose(filein);';
put 'rc = fclose(fileid);';
put 'run;';
put '%end;';
put '%mend;';
put 'filename sasjs temp lrecl=99999999;';
put 'data _null_;';
put 'file sasjs;';
put 'put ''<html><head>'';';
put 'put ''<meta http-equiv="Content-Security-Policy" content="frame-src ''''self'''' https://funhtml5games.com">'';';
put 'put ''</head><body style="background-color:black;text-align: center;">'';';
put 'put ''  <iframe src="https://funhtml5games.com?embed=sonic" style="width:496px;height:554px;border:none;" frameborder="0" scrolling="no"></iframe>'';';
put 'put '' '';';
put 'put '' '';';
put 'put ''</body></html>'';';
put 'run;';
put '%sasjsout(HTML)';
run;
%mm_createwebservice(path=&appLoc, name=sonic, code=sascode ,replace=yes)
filename sascode clear;
%let path=webv;