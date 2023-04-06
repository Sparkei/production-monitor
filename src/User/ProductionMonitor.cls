Class User.ProductionMonitor Extends %Persistent
{

ClientMethod onloadHandler() [ Language = javascript ]
{
zenPage.IntervalRefresh();
myVar1 = setInterval(zenPage.IntervalRefresh,1000);
}

ClientMethod IntervalRefresh() [ Language = javascript ]
{

var table = zenPage.getComponentById('services');
//Optional if Snapshot is used
//table.executeQuery()
table.refreshContents()
}

ClassMethod GetConfigItems() As %Status
{
	Set tStatement = ##class(%SQL.Statement).%New()
	Set tSC = tStatement.%PrepareClassQuery("Ens.Config.Production","EnumerateConfigItems")
	Write tSC,!
	#Dim exp As %Exception.SystemException
	#Dim rset As %SQL.StatementResult
	Set rset = tStatement.%Execute()
	Write rset,!
	Write rset.%SQLCODE,!
	While rset.%Next() {
		// ROWSPEC = "ConfigName:%String,CommentOrClassName:%String,Enabled:%Boolean,BusinessType:%Integer,ClassName:%String,RequestClasses:%String,ResponseClasses:%String,Production:%String,ItemId:%Integer,SeqNum:%String,BusPartner:%String,Categories:%String,AlertGroups:%String"
		//Write rset.%ROWCOUNT,!
		Try {
			Set tConfigName = rset.%GetData(1)
			Set tEnabled = rset.%GetData(3)
		} Catch exp {
			Write "CATCH",!
			Write exp,!
			Write exp.DisplayString(),!
		}
		Write $Get(tConfigName)," ",$Get(tEnabled),!
	}
	Quit tSC
}

/// Get information about currently running hosts and place it into
/// <var>pInfo</var> array.
ClassMethod GetHostInfo(ByRef pInfo, ByRef pSummary) As %Status
{
	Set tSC = $$$OK
	Try {

		#; host information
		#; run query to get stats, then group into buckets
		#dim tRS As %ResultSet
		Set tRS = ##class(%ResultSet).%New()
		Set tRS.ClassName = "Ens.Util.Statistics"
		Set tRS.QueryName = "EnumerateHostStatus"
		//zw tRS

		Set tSC = tRS.Execute()  Quit:$$$ISERR(tSC)

		Set filteredItemCount = 0
		Set filteredErrCount = 0

		While (tRS.Next(.tSC)) {  Quit:$$$ISERR(tSC)
		
			Set tBucket = tRS.Data("Type")
			Set tName = tRS.Data("Name")

			#; Skip internal services
			If (tName = "EnsLib.Testing.Service")||
				(tName = "Ens.ManagerService")||
				(tName = "Ens.ScheduleService")
				{
				Continue
			}

			#; Skip non-matching hosts if category specified
			Set tMatch = 0
			Set tId = $Get(^Ens.Runtime("ConfigItem",tName,"%Id"),0)
			If (tId > 0) {
				Set tCategories = ##class(Ens.Config.Item).CategoryGetStored(tId)
				If ($Get(currCategory) = "") {
					#; Current category is "All"
					If ($Get(allowedCategories) = "") {
						Set tMatch = 1
					} else {
						For i=1:1:$Length(tCategories,",") {
							Set tCat = $ZStrip($Piece(tCategories,",",i),"<>WC")
							If tCat '= "" && $G(tViewableCategoryArray(tCat),0) {
								Set tMatch = 1
								Quit
							}
						}
					}
				}
				
				If 'tMatch {
					Set filteredItemCount = filteredItemCount+1
					Set tState = $G(^CacheTemp.EnsHostMonitor($namespace,tName,"%Status"),-1)
					If (tState = "Error") {
						Set filteredErrCount = filteredErrCount+1
					}
					Continue
				}
			}
			
			Set tStatus = $ZCVT(tRS.Data("Status"),"U")
			Set tConnState = tRS.Data("AdapterState")

			#; Host status
			Set tIcon = ""
			Set tLamp = "#808080"
			Set tMsg = tStatus
			If (tStatus = "OK") {
				Set tLamp = "#80FF80"
			}
			If (tStatus = "DISABLED") {
				Set tIcon = "X"
			}
			If (tStatus = "ERROR") {
				Set tIcon = "!"
				Set tLamp = "#FF4040"
			}
			If (tStatus = "INACTIVE") {
				Set tIcon = "-"
				Set tLamp = "#FFFF80"
			}

			#; Adapter/Connection State
			Set tCIcon = "-"
			Set tCLamp = "#808080"
			If (tConnState [ " connected") {
				Set tCIcon = "+"
				Set tCLamp = "#80FF80"
			}
			If (tConnState [ " disconnected") {
				Set tCIcon = "x"
				Set tCLamp = "#FF4040"
			}
			If (tConnState [ " listening") {
				Set tCIcon = "o"
				Set tCLamp = "#FFFF80"
			}

			#; compose localized Connection State text
			Set (nConn,nDis,nListen)=0
			//Set tCMsg=$Case(tConnState,"disabled":$$$Text("disabled"), "n/a":$$$Text("n/a"),"unscheduled":$$$Text("unscheduled"),"not connecting":$$$Text("no jobs"),:"")
			Set tCMsg = ""
			If (tConnState = "disabled") Set tCMsg = tConnState
			If (tConnState = "n/a") Set tCMsg = tConnState
			If (tConnState = "unscheduled") Set tCMsg = tConnState
			If (tConnState = "not connecting") Set tCMsg = tConnState
			If tCMsg="" {
				Set tState(1)=$P(tConnState,",",1)
				Set tState(2)=$P(tConnState,",",2)
				Set tState(3)=$P(tConnState,",",3)
				For i=1:1:3 {
					Set:tState(i)[" connected" nConn = +tState(i)
					Set:tState(i)[" disconnected" nDis=+tState(i)
					Set:tState(i)[" listening" nListen=+tState(i)
				}
				Set tCMsg=""
				//Set:nConn||('nDis&&'nListen) tCMsg=$Case(nConn, 1:$$$Text("1 job connected"), :$$$FormatText($$$Text("%1 jobs connected"),nConn))
				//Set tCMsg = tCMsg_$Case(nDis, 0:"", 1:$S(""=tCMsg:"",1:", ")_$$$Text("1 job disconnected"), :$$$FormatText($$$Text("%1 jobs disconnected"),nDis))
				//Set tCMsg = tCMsg_$Case(nListen, 0:"", 1:$S(""=tCMsg:"",1:", ")_$$$Text("1 job listening"), :$$$FormatText($$$Text("%1 jobs listening"),nListen))
			}
			#; Assemble sorted pInfo package
			Set tID = tName
			Set tCount = tRS.Data("Count")

			Set tSort1 = $Case(tStatus,"OK":3,"ERROR":1,:2)
			Set tSort2 = $S(nDis:1,1:2)
			If ($Get(sortMode) = "Id") {
				Set tSort3 = $G(^Ens.Runtime("ConfigItem",tName,"%Id"),tName)
			} else {
				Set tSort3 = tName
			}

			Set pInfo(tBucket,tSort1,tSort2,tSort3) = $LB(tID,tName,tMsg,tLamp,tIcon,tCount,tCLamp,tCIcon,tCMsg,)
		}
		
		Quit:$$$ISERR(tSC)
	}
	Catch(ex) {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

/// Get information about currently running queues and place it into
/// <var>pInfo</var> array under "Queues".
ClassMethod GetQueueInfo(ByRef pInfo, ByRef pSummary) As %Status
{
	Set tSC = $$$OK
	Try {
		#; queue information
		Set tRS = ##class(%ResultSet).%New()
		Set tRS.ClassName = "Ens.Queue"
		Set tRS.QueryName = "Enumerate"
		
		Set tSC = tRS.Execute()
		Quit:$$$ISERR(tSC)

		Set n = 0
		Set tTotal = 0
		While (tRS.Next(.tSC)) {
			Quit:$$$ISERR(tSC)

			Set n = n + 1
			Set tCount = tRS.Data("Count")

			#; set lamp color by count
			Set tIcon = ""
			Set tLamp = $S(tCount<1:"#00FF00", tCount<10:"#40A000", tCount<50:"#808000", tCount<200:"orange",1:"#FF4040")
			Set tType = $S(tCount<1:"Queue is Empty", tCount<10:"Under 10", tCount<50:"Under 50", tCount<200:"Under 200",1:"Over 200")
			Set:tCount>=200 tIcon = "!"

			Set tTotal = tTotal + tCount
			Set tName = tRS.Data("Name")
			Set tID = tName

			Set tSort1 = -tCount
			Set tSort2 = tName

			Set tCount = $FN(tCount,",")

			Set pInfo("Queue",tSort1,tSort2,"zzz") = $LB(tID,tName,tType,tLamp,tIcon,tCount)
		}
		Quit:$$$ISERR(tSC)

		
			#; Suspended
		Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT  SourceConfigName ,count(SourceConfigName) as suspendnumber  From Ens.MessageHeader WHERE Status = 5 group by SourceConfigName")
			Set n = 0
		Set tTotal = 0
		While rs.%Next() {
		
			set tSusCount=rs.suspendnumber
			
		Set tName = rs.SourceConfigName
		Set tIcon = "S"
		Set tLamp = $S(tSusCount=0:"#00FF00",1:"orange")
		Set tType = $S(tSusCount<1:"None Suspended", tSusCount<10:"Under 10", tSusCount<50:"Under 50", tSusCount<200:"Under 200",1:"Over 200")

		Set pInfo("Queue",-tSusCount,"zzz","zzz") = $LB(tName,tName,tType,tLamp,tIcon,tSusCount)
		Set tTotal = tTotal + tSusCount
		}
			#;AlarmQueued 
		Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT  SourceConfigName,count(SourceConfigName) as AlarmQueuedCount FROM ens.messageheader WHERE targetconfigname='Ens.Alarm' and status=3 and MessageBodyClassName='Ens.AlarmRequest' and SourceConfigName !='Ens.ScheduleHandler' group by SourceConfigName" )
		
		While rs.%Next() {
		
			set tAlarmCount=rs.AlarmQueuedCount
			
		Set tName = rs.SourceConfigName
		Set tIcon = "P"
		Set tLamp = $S(tAlarmCount=0:"#00FF00",1:"orange")
		Set tType = $S(tAlarmCount<1:"None Suspended", tAlarmCount<10:"Under 10", tAlarmCount<50:"Under 50", tAlarmCount<200:"Under 200",1:"Over 200")

		Set pInfo("Queue",-tAlarmCount,"zzz","zzz") = $LB(tName,tName,tType,tLamp,tIcon,tAlarmCount)
		
		

		Set tTotal = tTotal + tAlarmCount
			
		}
		Set pSummary("Queue",1,tSort1,tSort2,"zzz") = $LB(tID,tName,tType,tLamp,tIcon,tCount)
			
		


	}
	Catch(ex) {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

Query SuspendedMessages() As %Query(ROWSPEC = "Name:%String,Count:%Integer") [ SqlProc ]
{
	SELECT '(susp) ' || TargetConfigName ,count(TargetConfigName)  From Ens.MessageHeader WHERE Status = 5 group by TargetConfigName
}

ClassMethod OutputTableIncomingOutgoing(pBucket As %String = "") As %Status
{
	Set tSC = ..GetHostInfo(.pInfo)
	&sql(SELECT Max(ID)- 10000000 INTO :tIDFrom fROM ENS.MessageHeader )
	If (pBucket = "") Set pBucket = $Order(pInfo(pBucket))
	Set tSort1 = ""
	if pBucket="BusinessService"
	{
	Write "<tr>",!
	Write "<th>Stat </th>"
	Write "<th>AStat </th>"
	Write "<th><b>Business Service</b></th>"	
	Write "<th><b>Last Successful<br> Message</b></th>"	
	Write "</tr>",!
	}
	
	if pBucket="BusinessOperation"
	{
	Write "<tr>",!
	Write "<th>Stat</th>"
	Write "<th>AStat</th>"
	Write "<th><b>Business Operation</b></th>"	
	Write "<th><b>Last Successful <br> Message</b></th>"	
	Write "</tr>",!
	}
		
	For {
		Set tSort1 = $Order(pInfo(pBucket,tSort1))
		If (tSort1 = "") { QUIT }
		Set tSort2 = ""
		For {
			Set tSort2 = $Order(pInfo(pBucket,tSort1,tSort2))
			If (tSort2 = "") { QUIT }
			Set tSort3 = ""
			For {
				Set tSort3 = $Order(pInfo(pBucket,tSort1,tSort2,tSort3),1,tData)
				If (tSort3 = "") || ($ListGet(tData,9)=0){ QUIT }
				Set tID = $ListGet(tData,1)
				Set tName = $ListGet(tData,2)
				Set tMsg = $ListGet(tData,3)
				Set tLamp = $ListGet(tData,4)
				Set tIcon = $ListGet(tData,5)
				Set tCount = $ListGet(tData,6)
				Set tCLamp = $ListGet(tData,7)
				Set tCIcon = $ListGet(tData,8)
				Set tCMsg = $ListGet(tData,9)
				
				if ((tMsg="ERROR")||(tMsg="INACTIVE") || (tMsg="RETRY")){
				Write "<tr>",!
				Write "<td class='Lamp' style='background:",tLamp,";'>",tIcon,"</td>",!
				Write "<td class='Lamp' style='background:",tCLamp,";'>",tCIcon,"</td>",!
				Write "<td>",tID ,"</td>",!
				//get last message 
				if pBucket="BusinessService"{
					if $USERNAME="UnknownUser"
					{Write "<td>","NotLoggedIn","</td>",!}
					else
					{
				set tSql="SELECT TOP 1  TimeCreated as LastMessage"
				set tSql=tSql_" FROM Ens.MessageHeader WHERE ID IN (  SELECT TOP 1 ID FROM Ens.MessageHeader"
            	set tSql=tSql_" WHERE SourceConfigName = '"_tID
                set tSql=tSql_"' and TargetConfigName <>'Ens.Alert' and Status ='Completed' ORDER BY ID DESC UNION SELECT TOP 1 ID FROM Ens.MessageHeader"
            	set tSql=tSql_" WHERE TargetConfigName = '"_tID_"' and Status ='Completed' ORDER BY ID DESC)ORDER BY ID DESC "
 				set tStatement = ##class(%SQL.Statement).%New("2")
 				set qStatus = tStatement.%Prepare(tSql)
 				if qStatus'=1 {write "%Prepare failed:" do $System.Status.DisplayError(qStatus) quit}
  				set rs = tStatement.%Execute()
  				
				while rs.%Next() {
				Write "<td>",rs.LastMessage,"</td>",!}
				//Write "<td>",tSQL,"</td>",!}
				}
				}
				if pBucket="BusinessOperation"{
					
					if $USERNAME="UnknownUser"
					{Write "<td>","NotLoggedIn","</td>",!}
					else
					{
				set tSql="SELECT TOP 1 TimeCreated as LastMessage FROM Ens.MessageHeader WHERE ID IN ( SELECT TOP 1 ID FROM Ens.MessageHeader WHERE SourceConfigName = "
				set tSql=tSql_"'"_tID_"' "
				set tSql=tSql_"and TargetConfigName <>'Ens.Alert' and IsError=0 and  Status ='Completed' ORDER BY ID DESC UNION SELECT TOP 1 ID FROM Ens.MessageHeader WHERE TargetConfigName = "
				set tSql=tSql_"'"_tID_"' "
				set tSql=tSql_"and IsError=0 and Status ='Completed' ORDER BY ID DESC)ORDER BY ID DESC "
				
 				set tStatement = ##class(%SQL.Statement).%New("2")
 				set qStatus = tStatement.%Prepare(tSql)
 				if qStatus'=1 {write "LastMessageError:" do $System.Status.DisplayError(qStatus) quit}
  				set rs = tStatement.%Execute()
  				
				while rs.%Next() {
				Write "<td>",rs.LastMessage,"</td>",!}
				//Write "<td>",tSQL,"</td>",!}
				}
			}
				
				Write "</tr>",!
				}
				
			}
		}
	}
	Quit $$$OK
}

ClassMethod OutputTablePMQ(pBucket As %String = "") As %Status
{
	Set tSC = ..GetQueueInfo(.pInfo)
	If (pBucket = "") Set pBucket = $Order(pInfo(pBucket))
	Set tSort1 = ""
		Write "<tr>",!
				Write "<th>Stat </th>"
				Write "<th><b>Name</b></th>"	
				Write "<th><b>Queue Count</th>"	
				Write "<th><b>Oldest Msg</th>"		
				Write "</tr>",!	
				Write "<tr>",!
	For {
		Set tSort1 = $Order(pInfo(pBucket,tSort1))
		If (tSort1 = "") { QUIT }
		Set tSort2 = ""
		For {
			Set tSort2 = $Order(pInfo(pBucket,tSort1,tSort2))
			If (tSort2 = "") { QUIT }
			Set tSort3 = ""
			For {
				Set tSort3 = $Order(pInfo(pBucket,tSort1,tSort2,tSort3),1,tData)
				If (tSort3 = "") { QUIT }
				Set tID = $ListGet(tData,1)
				Set tName = $ListGet(tData,2)
				Set tMsg = $ListGet(tData,3)
				Set tLamp = $ListGet(tData,4)
				Set tIcon = $ListGet(tData,5)
				Set tCount = $ListGet(tData,6)
				if tCount>=1{
			
				Write "<td class='Lamp' style='background:",tLamp,";'>",tIcon,"</td>",!
				Write "<td class ='QueueDetails'>",tID,"</td>",!
				Write "<td style='text-align:right;' nowrap title='Number of messages in this queue'>&nbsp;",tCount,"<br>"
					//QueuedFrom
				
				w "</td>"
				
				w "<td>"
				set tSql="select min(TimeCreated) as QueuedFrom From Ens.MessageHeader where TargetConfigName ='"_tID_ "' and Status='Queued'" 
				set tStatement = ##class(%SQL.Statement).%New("2")
				set qStatus = tStatement.%Prepare(tSql)
				if qStatus'=1 {write "%Prepare failed:" do $System.Status.DisplayError(qStatus) quit}
				set rs = tStatement.%Execute()
				while rs.%Next() 
				{
					Write $EXTRACT(rs.QueuedFrom,0,16)
					
				}
				w "</td>"
				W "</tr>",!
				//Get the Oldest Queue message
				 
				
				}
			}
		}
	}
	Quit $$$OK
}

ClassMethod Test() As %Status
{
	Set tSC = ..GetHostInfo(.tStats,.tSummary)
	zw tStats
	zw tSummary
	Quit $$$OK
	
	Set tStatement = ##class(%SQL.Statement).%New()
	Set tSC = tStatement.%PrepareClassQuery("Ens.Config.Production","EnumerateConfigItems")
	Write tSC,!
	#Dim exp As %Exception.SystemException
	#Dim rset As %SQL.StatementResult
	Set rset = tStatement.%Execute()
	Write rset,!
	Write rset.%SQLCODE,!
	While rset.%Next() {
		// ROWSPEC = "ConfigName:%String,CommentOrClassName:%String,Enabled:%Boolean,BusinessType:%Integer,ClassName:%String,RequestClasses:%String,ResponseClasses:%String,Production:%String,ItemId:%Integer,SeqNum:%String,BusPartner:%String,Categories:%String,AlertGroups:%String"
		//Write rset.%ROWCOUNT,!
		Try {
			Set tConfigName = rset.%GetData(1)
			Set tEnabled = rset.%GetData(3)
		} Catch exp {
			Write "CATCH",!
			Write exp,!
			Write exp.DisplayString(),!
		}
		Write $Get(tConfigName)," ",$Get(tEnabled),!
	}
	Quit tSC
}

Storage Default
{
<Data name="ProductionMonitorDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
</Data>
<DataLocation>^Component5976.ProductionM5A6AD</DataLocation>
<DefaultData>ProductionMonitorDefaultData</DefaultData>
<IdLocation>^Component5976.ProductionM5A6AD</IdLocation>
<IndexLocation>^Component5976.ProductionM5A6AI</IndexLocation>
<StreamLocation>^Component5976.ProductionM5A6AS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
