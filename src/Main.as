// Global variables
int totalPlayers = 0;
array<string> accountIds;
UserResultVM vm = UserResultVM();
float refreshProgress = 0;

void Render()
{
#if TMNEXT

    if (hasPermissionAndIsCOTDRunning())
    {
        if (!UI::IsGameUIVisible() && settings_hideIfUIHidden)
        {
            return;
        }

        if(!UI::IsOverlayShown() && onlyOnOverlay)
        {
            return;
        }

        COTDClubLiveUI::renderUI(vm, refreshProgress);
    }
#endif
}

void RenderMenu()
{
#if TMNEXT
    if(UI::MenuItem("\\$f0c\\$s" + Icons::Bold + "\\$z COTD Live Qualifying", "", windowVisible)) {
        windowVisible = !windowVisible;
    }
#endif
}

void Main()
{  
#if TMNEXT    
    auto app = cast<CTrackMania>(GetApp());
    auto network = cast<CTrackManiaNetwork>(app.Network);

    NadeoServices::AddAudience("NadeoLiveServices");

    bool settings_changed = false;
    int friendsRefreshIndicator = 4; //Refreshes friends every 60 seconds

    while (!NadeoServices::IsAuthenticated("NadeoLiveServices"))
    {
        yield();
    }

    while(true)
    {
        if (hasPermissionAndIsCOTDRunning())
        {
            settings_changed = checkSettingsChanged();
            if(settings_changed)
            {
                accountIds = {};
            }

            array<string> displayModes = {};

            NadeoCotdApi nadeoCotdApi;
            MapMonitorCotdApi mapMonitorCotdApi;

            ICotdApi@ cotdApi;
            if (settings_cotdApi == CotdApi::Nadeo)
            {
                @cotdApi = @nadeoCotdApi;
            }
            else if (settings_cotdApi == CotdApi::MapMonitor)
            {
                @cotdApi = @mapMonitorCotdApi;
            }
                  
            string currentUserId = NadeoCoreAPI::getCurrentWebServicesUserId();           
            string mapid = network.ClientManiaAppPlayground.Playground.Map.MapInfo.MapUid;

            friendsRefreshIndicator++;
            
            if (state_currentChallengeid == 0)
            {
                state_currentChallengeid = cotdApi.GetCurrentCOTDChallengeId();
            }

            array<Result@> allResults = {};
            array<Result@> topResults = {};

            //Club
            if(settings_showClub)
            {
                //Only reload club members if new club was selected or if displaymode was changed from club to friends
                if (settings_changed)
                {
                    if (settings_clubId == 0)
                    {
                        state_currentClubName = "$F33Please select a Club in the settings.";
                    }
                    else
                    {                
                        state_currentClubName = NadeoLiveServicesAPI::GetClubName(settings_clubId);
                        addToAccountIds(NadeoLiveServicesAPI::GetAllMemberIdsFromClub(settings_clubId, getMaxedTrackedPlayers()));
                    }
                }
            }
            state_showClub = settings_showClub;
            state_currentClubId = settings_clubId;

            //Friends
            if(settings_showFriends)
            {
                if(settings_changed || friendsRefreshIndicator >= 4)
                {
                    addToAccountIds(NadeoCoreAPI::GetFriendList(getMaxedTrackedPlayers()));
                    friendsRefreshIndicator = 0;                                              
                } 
            }
            state_showFriends = settings_showFriends;  

            //Custom Players
            if(settings_showCustomPlayers)
            {
                if(settings_changed && settings_customPlayers.Length >= 36) //atleast 1 player    
                {     
                    state_customPlayerListArray = settings_customPlayers.Split("\n");
                    addToAccountIds(state_customPlayerListArray);
                } 
            }    
            state_showCustom = settings_showCustomPlayers;  
            state_customPlayerList = settings_customPlayers;     

            //Add local user if not already included
            if (accountIds.Find(currentUserId) < 0)
            {
                accountIds.InsertLast(currentUserId);
            }

            array<Result@> playerResults = cotdApi.GetCurrentStandingForPlayers(accountIds, state_currentChallengeid, mapid);

            for(uint n = 0; n < playerResults.Length; n++ )
            {
                allResults.InsertLast(playerResults[n]);
            }

            allResults.SortAsc();

            for(uint n = 0; n < numberOfPlayerDisplay && n < allResults.Length; n++ )
            {
                topResults.InsertLast(allResults[n]);
            }

            array<SingleUserResultVM@> singleResultVMs = VMMapper::ToSingleUserResultVMs(topResults);

            //Show Div 1 Cutoff
            if (settings_showDivOneCutoff)
            {
                Result@ cutoff = cotdApi.GetDiv1CutoffTime(state_currentChallengeid, mapid);
                if (@cutoff != null)
                {
                    SingleUserResultVM@ cutoffVM = VMMapper::ToSingleUserResultCutoffVM(cutoff);
                    singleResultVMs.InsertLast(cutoffVM);
                    singleResultVMs.SortAsc();
                }
            }
            state_showDivOneCutoff = settings_showDivOneCutoff;

            vm = VMMapper::ToUserResultVM(buildDisplayModeList(state_currentClubName), singleResultVMs);
            settings_changed = false;
            state_forceRefreshPlayers = false;

        } else {
            //Reset state once COTD quali ends
            state_currentChallengeid = 0;
            vm = UserResultVM();
            accountIds = {};
            totalPlayers = 0;
            state_forceRefreshPlayers = true;
        }

        float progress = 100;
        int progressBarInterval = 60;
        float refreshTime = 15000;
        while(refreshTime >= progress)
        {
            if (progress != 0)
            {
                refreshProgress = 1 - (progress / refreshTime);
            }
            progress = progress + progressBarInterval;
            sleep(progressBarInterval);
        }       
    }
#endif
}

bool hasPermissionAndIsCOTDRunning()
{
    auto app = cast<CTrackMania>(GetApp());
    auto network = cast<CTrackManiaNetwork>(app.Network);
    auto server_info = cast<CTrackManiaNetworkServerInfo>(network.ServerInfo);
    return Permissions::PlayOnlineCompetition() && network.ClientManiaAppPlayground !is null && network.ClientManiaAppPlayground.Playground !is null && network.ClientManiaAppPlayground.Playground.Map !is null && server_info.CurGameModeStr == "TM_COTDQualifications_Online";
}

uint getMaxedTrackedPlayers()
{
    if (settings_cotdApi == CotdApi::Nadeo)
    {
        return 100;
    }
    else if (settings_cotdApi == CotdApi::MapMonitor)
    {
        return 1000;
    }
    return 0;
}

void addToAccountIds(array<string> fetchedPlayers)
{
    for(uint p = 0; p < fetchedPlayers.Length; p++)
    {
        if (accountIds.Find(fetchedPlayers[p]) < 0 && accountIds.Length < getMaxedTrackedPlayers())
        {
            accountIds.InsertLast(fetchedPlayers[p]);
        }
    }
}

array<string> buildDisplayModeList(const string &in clubName)
{
    if(!settings_showClub && !settings_showFriends && !settings_showCustomPlayers)
    {
       return {"$F33No opponents selected!\n $FFFYou can select\n- Club\n- Friends\n- Custom Players"};
    }

    array<string> displayModeNames = {};
    if (settings_showClub)
    {
        displayModeNames.InsertLast(clubName);
    }
    if (settings_showFriends)
    {
        displayModeNames.InsertLast("Friends");
    }
    if (settings_showCustomPlayers)
    {
        displayModeNames.InsertLast("Custom");
    }
    return displayModeNames;
}
