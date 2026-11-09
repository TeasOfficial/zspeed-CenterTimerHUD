#include <sourcemod>

#include <morecolors>
#include <clientprefs>
#include <DynamicChannels>
#include <cookiemgr>

#include <shavit/core>
#include <shavit/replay-playback>
#include <shavit/zones>
#include <shavit/wr>
#include <wrsj>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
	name        = "Center Timer & Finish Diff HUD",
	author      = "Picrisol45",
	description = "Timer HUD + Finish comparison HUD (WR/SR/PB), only support shavit's bhoptimer",
	version     = "1.0",
	url         = ""
};

/* ------------------ Defaults ------------------ */

// Time HUD
#define DEFAULT_SHOW_TIME             false
#define DEFAULT_TIME_POSITION_Y       0.62
#define DEFAULT_COLOR_TIME            "Green"
#define DEFAULT_COLOR_PRACTICE        "White"
#define DEFAULT_COLOR_STARTZONE       "White"
#define DEFAULT_COLOR_COMPLETION      "Cyan"

#define TIME_PRECISION_TENTH          1
#define TIME_PRECISION_HUNDREDTH      2
#define TIME_PRECISION_THOUSANDTH     3
#define DEFAULT_TIME_PRECISION        TIME_PRECISION_THOUSANDTH

// Finish Diff HUD
#define DEFAULT_FINISH_DIFF                 true
#define DEFAULT_FINISH_DIFF_MODE            0
#define DEFAULT_FINISH_DIFF_POSITION_Y      0.66
#define DEFAULT_FINISH_TIME_POSITION_Y      0.62
#define DEFAULT_FINISH_DIFF_SHOW_PREFIX     false
#define DEFAULT_FINISH_TIME                 true
#define DEFAULT_COLOR_FINISH_FASTER         "Green"
#define DEFAULT_COLOR_FINISH_SLOWER         "Red"

// Delays must be float literals (3.0, not 3); CreateDataTimer takes a float
#define FINISH_DIFF_DELAY   0.3
#define FINISH_TIME_DELAY   0.1

#define POSITION_CENTER   -1.0
#define DEFAULT_FINISH_DIFF_POSITION_X  POSITION_CENTER
#define DEFAULT_FINISH_TIME_POSITION_X  POSITION_CENTER
#define HUD_BUF_SIZE      64

// Redraw the timer HUD every N usercmds (~9 updates/sec at 66 tick).
#define TIME_HUD_CMD_INTERVAL  7

// Redraw interval for the position-menu preview marker.
#define POSITION_PREVIEW_INTERVAL  0.2

/* ------------------------------------------------------ */

enum
{
	AXIS_X = 0,
	AXIS_Y
};

enum HUDType
{
	HUD_TIME = 0,
	HUD_FINISH
};

enum FinishDiffMode
{
	FINISH_DIFF_WR = 0,
	FINISH_DIFF_SR,
	FINISH_DIFF_PB
};

enum RGBType
{
	RGB_INVALID = -1,
	RGB_TIME = 0,
	RGB_PRACTICE,
	RGB_STARTZONE,
	RGB_COMPLETION,
	RGB_FINISH_FASTER,
	RGB_FINISH_SLOWER,
	RGB_MAX
};

// ---- Timer settings ----

enum struct TimeCookies
{
	Cookie showTime;
	Cookie timePositionX;
	Cookie timePositionY;
	Cookie timePrecision;
	Cookie colorTime;
	Cookie colorTimeInPractice;
	Cookie colorTimeInStartZone;
	Cookie colorTimeCompletion;
}

enum struct TimeSettings
{
	bool showTime;
	float timePosition[2];
	int timePrecision;
	int colorTime[3];
	int colorTimeInPractice[3];
	int colorTimeInStartZone[3];
	int colorTimeCompletion[3];
}

// ---- Finish Diff settings ----

enum struct FinishDiffCookies
{
	Cookie finishDiffEnabled;
	Cookie finishDiffMode;
	Cookie finishDiffPositionX;
	Cookie finishDiffPositionY;
	Cookie finishTimePositionX;
	Cookie finishTimePositionY;
	Cookie finishDiffShowPrefix;
	Cookie finishTimeEnabled;
	Cookie colorFinishFaster;
	Cookie colorFinishSlower;
}

enum struct FinishDiffSettings
{
	bool showFinishDiff;
	int finishDiffMode;
	float finishDiffPosition[2];
	float finishTimePositionX;
	float finishTimePositionY;
	int finishDiffColorFaster[3];
	int finishDiffColorSlower[3];
	bool finishDiffShowPrefix;
	bool showFinishTime;
}

TimeCookies T_Cookies;
TimeSettings T_Settings[MAXPLAYERS + 1];

FinishDiffCookies F_Cookies;
FinishDiffSettings F_Settings[MAXPLAYERS + 1];

bool gB_SettingAxis[MAXPLAYERS + 1];
bool gB_ReplayPlayback = false;
HUDType g_PositionMenuSource[MAXPLAYERS + 1];
RGBType g_CurrentRGBType[MAXPLAYERS + 1];
float gF_Modifier[MAXPLAYERS + 1];
float gF_LastRunTime[MAXPLAYERS + 1];
float g_fWRTime = 0.0;
char g_sWRMap[PLATFORM_MAX_PATH];
Handle gH_SyncFinishDiff;
Handle gH_SyncFinishTime;
int g_RGBStep[MAXPLAYERS + 1];
bool gB_InFinishDiffColorMenu[MAXPLAYERS + 1];

bool gB_PreviewActive[MAXPLAYERS + 1];
Menu gH_PositionMenu[MAXPLAYERS + 1];
HUDType g_PositionMenuOrigin[MAXPLAYERS + 1];

static const char g_ColorNames[][] =
{
	"White", "Red", "Green", "LightGreen", "Blue",
	"Cyan", "Orange", "Yellow", "Purple"
};

static const int g_ColorValues[][3] =
{
	{255,255,255}, {255,0,0}, {0,255,0}, {60,145,10},
	{30,140,255}, {0,255,255}, {230,72,16}, {255,255,0}, {180,0,255}
};

// Indexed by RGBType.
static const char g_RGBDefaults[][] =
{
	DEFAULT_COLOR_TIME,
	DEFAULT_COLOR_PRACTICE,
	DEFAULT_COLOR_STARTZONE,
	DEFAULT_COLOR_COMPLETION,
	DEFAULT_COLOR_FINISH_FASTER,
	DEFAULT_COLOR_FINISH_SLOWER
};

static const char g_RGBTypeNames[][] =
{
	"Time HUD Color",
	"Practice Time Color",
	"Start Zone Time Color",
	"Finish Time Color",
	"Finish Diff Faster Color",
	"Finish Diff Slower Color"
};

public void OnPluginStart()
{
	// Time HUD commands
	RegConsoleCmd("sm_thud", Command_TimeHUDMenu, "Time HUD settings.");
	RegConsoleCmd("sm_th", Command_TimeHUDMenu, "Time HUD settings.");

	// Finish Diff commands
	RegConsoleCmd("sm_finishdiff", Command_FinishDiffMenu, "Finish Diff settings.");
	RegConsoleCmd("sm_fd", Command_FinishDiffMenu, "Finish Diff settings.");

	// Time cookies
	T_Cookies.showTime = new Cookie("zspeed_show_time", "[zSpeed] Time HUD", CookieAccess_Protected);
	T_Cookies.timePositionX = new Cookie("zspeed_time_positionx", "[zSpeed] Time HUD Position (x)", CookieAccess_Protected);
	T_Cookies.timePositionY = new Cookie("zspeed_time_positiony", "[zSpeed] Time HUD Position (y)", CookieAccess_Protected);
	T_Cookies.timePrecision = new Cookie("zspeed_time_precision", "[zSpeed] Time Decimal Places", CookieAccess_Protected);
	T_Cookies.colorTime = new Cookie("zspeed_color_time", "[zSpeed] Time HUD Color", CookieAccess_Protected);
	T_Cookies.colorTimeInPractice = new Cookie("zspeed_color_time_practice", "[zSpeed] Time HUD Practice Color", CookieAccess_Protected);
	T_Cookies.colorTimeInStartZone = new Cookie("zspeed_color_time_startzone", "[zSpeed] Time HUD Start Zone Color", CookieAccess_Protected);
	T_Cookies.colorTimeCompletion = new Cookie("zspeed_color_time_completion", "[zSpeed] Time HUD Finish Color", CookieAccess_Protected);

	// Finish Diff cookies
	F_Cookies.finishDiffEnabled = new Cookie("zspeed_finish_diff_enabled", "[zSpeed] Finish Diff Enabled", CookieAccess_Protected);
	F_Cookies.finishDiffMode = new Cookie("zspeed_finish_diff_mode", "[zSpeed] Finish Diff Mode", CookieAccess_Protected);
	F_Cookies.finishDiffPositionX = new Cookie("zspeed_finish_diff_positionx", "[zSpeed] Finish Diff Position (x)", CookieAccess_Protected);
	F_Cookies.finishDiffPositionY = new Cookie("zspeed_finish_diff_positiony", "[zSpeed] Finish Diff Position (y)", CookieAccess_Protected);
	F_Cookies.finishTimePositionX = new Cookie("zspeed_finish_time_positionx", "[zSpeed] Finish Time Position (x)", CookieAccess_Protected);
	F_Cookies.finishTimePositionY = new Cookie("zspeed_finish_time_positiony", "[zSpeed] Finish Time Position (y)", CookieAccess_Protected);
	F_Cookies.finishDiffShowPrefix = new Cookie("zspeed_finish_diff_show_prefix", "[zSpeed] Finish Diff Show Prefix", CookieAccess_Protected);
	F_Cookies.finishTimeEnabled = new Cookie("zspeed_finish_time_enabled", "[zSpeed] Finish Time Enabled", CookieAccess_Protected);
	F_Cookies.colorFinishFaster = new Cookie("zspeed_color_finish_faster", "[zSpeed] Finish Diff Faster Color", CookieAccess_Protected);
	F_Cookies.colorFinishSlower = new Cookie("zspeed_color_finish_slower", "[zSpeed] Finish Diff Slower Color", CookieAccess_Protected);

	gH_SyncFinishDiff = CreateHudSynchronizer();
	gH_SyncFinishTime = CreateHudSynchronizer();

	gB_ReplayPlayback = LibraryExists("shavit-replay-playback");

	CreateTimer(POSITION_PREVIEW_INTERVAL, Timer_PositionPreview, _, TIMER_REPEAT);

	// Initialise per-client state even for clients that were already in-game
	// when the plugin was (re)loaded; cookie cache may or may not be ready.
	for (int i = 1; i <= MaxClients; i++)
	{
		ResetClientState(i);

		if (AreClientCookiesCached(i))
			OnClientCookiesCached(i);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "shavit-replay-playback"))
	{
		gB_ReplayPlayback = true;
	}
	else if (StrEqual(name, "wrsj") && g_sWRMap[0] != '\0')
	{
		WRSJ_QueryMap(g_sWRMap, true);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "shavit-replay-playback"))
		gB_ReplayPlayback = false;
	else if (StrEqual(name, "wrsj"))
		g_fWRTime = 0.0;
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client);

	// clientprefs may cache before or after PutInServer; re-apply if it already ran.
	if (AreClientCookiesCached(client))
		OnClientCookiesCached(client);
}

public void OnMapStart()
{
	GetCurrentMap(g_sWRMap, sizeof(g_sWRMap));
	g_fWRTime = 0.0;

	for (int i = 1; i <= MaxClients; i++)
	{
		gB_PreviewActive[i] = false;
		gH_PositionMenu[i] = null;
		g_PositionMenuOrigin[i] = HUD_TIME;
	}

	if (LibraryExists("wrsj"))
		WRSJ_QueryMap(g_sWRMap, true);
}

public void WRSJ_OnQueryFinished(const char map[PLATFORM_MAX_PATH], ArrayList records)
{
	if (!StrEqual(map, g_sWRMap) || records == null || records.Length == 0)
		return;

	WRSJ_RecordInfo info;
	records.GetArray(0, info, sizeof(info));
	g_fWRTime = StringToFloat(info.time);
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp)
{
	if (!IsValidClient(client) || IsFakeClient(client))
		return;

	gF_LastRunTime[client] = time;

	// Queue the finish diff with its own delay.
	DataPack pack;
	CreateDataTimer(FINISH_DIFF_DELAY, Timer_ShowFinishDiff, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(GetClientSerial(client));
	pack.WriteCell(style);
	pack.WriteFloat(time);
	pack.WriteFloat(oldtime);
	pack.WriteCell(track);

	SendFinishTimeHUD(client, client, time);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client || !IsValidClient(i) || IsFakeClient(i))
			continue;

		if (GetSpectatorTarget(i, i) == client)
			SendFinishTimeHUD(i, client, time);
	}
}

public Action Timer_ShowFinishDiff(Handle timer, DataPack pack)
{
	pack.Reset();

	int client = GetClientFromSerial(pack.ReadCell());
	int style = pack.ReadCell();
	float time = pack.ReadFloat();
	float oldtime = pack.ReadFloat();
	int track = pack.ReadCell();

	if (client == 0 || !IsValidClient(client) || IsFakeClient(client))
		return Plugin_Stop;

	DrawFinishDiffHUD(client, style, time, oldtime, track);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client || !IsValidClient(i) || IsFakeClient(i))
			continue;

		if (GetSpectatorTarget(i, i) == client)
			DrawFinishDiffHUD(i, style, time, oldtime, track);
	}

	return Plugin_Stop;
}

void SendFinishTimeHUD(int viewer, int finisher, float time)
{
	if (!F_Settings[viewer].showFinishTime)
		return;

	// Each finish HUD uses its own delay macro; enabling one never changes
	// the timing of the other.
	DataPack pack;
	CreateDataTimer(FINISH_TIME_DELAY, Timer_ShowFinishTime, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(GetClientSerial(viewer));
	pack.WriteCell(GetClientSerial(finisher));
	pack.WriteFloat(time);
}

public Action Timer_ShowFinishTime(Handle timer, DataPack pack)
{
	pack.Reset();

	int viewer = GetClientFromSerial(pack.ReadCell());
	int finisher = GetClientFromSerial(pack.ReadCell());
	float time = pack.ReadFloat();

	if (viewer == 0 || !IsValidClient(viewer) || IsFakeClient(viewer))
		return Plugin_Stop;

	if (finisher == 0 || !IsValidClient(finisher) || IsFakeClient(finisher))
		return Plugin_Stop;

	if (viewer != finisher && GetSpectatorTarget(viewer, viewer) != finisher)
		return Plugin_Stop;

	DrawFinishTimeHUD(viewer, time);
	return Plugin_Stop;
}

/* -- Cookies -- */

public void OnClientCookiesCached(int client)
{
	CheckFreshManTimer(client);
	CheckFreshManFinishDiff(client);
	EnsureColorCookies(client);

	// Load timer settings
	T_Settings[client].showTime             = GetCookie(client, T_Cookies.showTime, CT_Boolean);
	T_Settings[client].timePosition[AXIS_X] = GetCookie(client, T_Cookies.timePositionX, CT_Float);
	T_Settings[client].timePosition[AXIS_Y] = GetCookie(client, T_Cookies.timePositionY, CT_Float);

	int precision = GetCookie(client, T_Cookies.timePrecision, CT_Integer);
	T_Settings[client].timePrecision =
		(precision >= TIME_PRECISION_TENTH && precision <= TIME_PRECISION_THOUSANDTH)
			? precision : DEFAULT_TIME_PRECISION;

	// Load finish diff settings
	F_Settings[client].showFinishDiff = GetCookie(client, F_Cookies.finishDiffEnabled, CT_Boolean);
	F_Settings[client].finishDiffPosition[AXIS_X] = GetCookie(client, F_Cookies.finishDiffPositionX, CT_Float);
	F_Settings[client].finishDiffPosition[AXIS_Y] = GetCookie(client, F_Cookies.finishDiffPositionY, CT_Float);
	F_Settings[client].finishTimePositionX = GetCookie(client, F_Cookies.finishTimePositionX, CT_Float);
	F_Settings[client].finishTimePositionY = GetCookie(client, F_Cookies.finishTimePositionY, CT_Float);
	F_Settings[client].finishDiffShowPrefix = GetCookie(client, F_Cookies.finishDiffShowPrefix, CT_Boolean);
	F_Settings[client].showFinishTime = GetCookie(client, F_Cookies.finishTimeEnabled, CT_Boolean);

	int mode = GetCookie(client, F_Cookies.finishDiffMode, CT_Integer);
	F_Settings[client].finishDiffMode =
		(mode >= view_as<int>(FINISH_DIFF_WR) && mode <= view_as<int>(FINISH_DIFF_PB))
			? mode : DEFAULT_FINISH_DIFF_MODE;

	// Load colors
	char sColor[32];
	for (int i = 0; i < view_as<int>(RGB_MAX); i++)
	{
		RGBType type = view_as<RGBType>(i);
		Cookie cookie = GetColorCookie(type);
		cookie.Get(client, sColor, sizeof(sColor));

		int color[3];
		ApplyColorByNameRaw(sColor, color);
		SetRGBSettings(client, type, color);
	}
}

void CheckFreshManTimer(int client)
{
	EnsureCookie(client, T_Cookies.showTime, CT_Boolean, DEFAULT_SHOW_TIME);
	EnsureCookie(client, T_Cookies.timePrecision, CT_Integer, DEFAULT_TIME_PRECISION);
	EnsureCookie(client, T_Cookies.timePositionX, CT_Float, POSITION_CENTER);
	EnsureCookie(client, T_Cookies.timePositionY, CT_Float, DEFAULT_TIME_POSITION_Y);
}

void CheckFreshManFinishDiff(int client)
{
	EnsureCookie(client, F_Cookies.finishDiffEnabled, CT_Boolean, DEFAULT_FINISH_DIFF);
	EnsureCookie(client, F_Cookies.finishDiffMode, CT_Integer, DEFAULT_FINISH_DIFF_MODE);
	EnsureCookie(client, F_Cookies.finishDiffPositionX, CT_Float, DEFAULT_FINISH_DIFF_POSITION_X);
	EnsureCookie(client, F_Cookies.finishDiffPositionY, CT_Float, DEFAULT_FINISH_DIFF_POSITION_Y);
	EnsureCookie(client, F_Cookies.finishTimePositionX, CT_Float, DEFAULT_FINISH_TIME_POSITION_X);
	EnsureCookie(client, F_Cookies.finishTimePositionY, CT_Float, DEFAULT_FINISH_TIME_POSITION_Y);
	EnsureCookie(client, F_Cookies.finishDiffShowPrefix, CT_Boolean, DEFAULT_FINISH_DIFF_SHOW_PREFIX);
	EnsureCookie(client, F_Cookies.finishTimeEnabled, CT_Boolean, DEFAULT_FINISH_TIME);
}

void EnsureCookie(int client, Cookie cookie, CookieType type, any value)
{
	char sValue[32];
	cookie.Get(client, sValue, sizeof(sValue));

	if (sValue[0] == '\0')
		SetCookie(client, cookie, type, value);
}

void EnsureColorCookies(int client)
{
	char sValue[32];

	for (int i = 0; i < view_as<int>(RGB_MAX); i++)
	{
		Cookie cookie = GetColorCookie(view_as<RGBType>(i));
		cookie.Get(client, sValue, sizeof(sValue));

		if (sValue[0] == '\0')
			cookie.Set(client, g_RGBDefaults[i]);
	}
}

void OnCookieChangedTime(int client)
{
	SetCookie(client, T_Cookies.showTime, CT_Boolean, T_Settings[client].showTime);
	SetCookie(client, T_Cookies.timePositionX, CT_Float, T_Settings[client].timePosition[AXIS_X]);
	SetCookie(client, T_Cookies.timePositionY, CT_Float, T_Settings[client].timePosition[AXIS_Y]);
	SetCookie(client, T_Cookies.timePrecision, CT_Integer, T_Settings[client].timePrecision);
}

void OnCookieChangedFinishDiff(int client)
{
	SetCookie(client, F_Cookies.finishDiffEnabled, CT_Boolean, F_Settings[client].showFinishDiff);
	SetCookie(client, F_Cookies.finishDiffMode, CT_Integer, F_Settings[client].finishDiffMode);
	SetCookie(client, F_Cookies.finishDiffPositionX, CT_Float, F_Settings[client].finishDiffPosition[AXIS_X]);
	SetCookie(client, F_Cookies.finishDiffPositionY, CT_Float, F_Settings[client].finishDiffPosition[AXIS_Y]);
	SetCookie(client, F_Cookies.finishTimePositionX, CT_Float, F_Settings[client].finishTimePositionX);
	SetCookie(client, F_Cookies.finishTimePositionY, CT_Float, F_Settings[client].finishTimePositionY);
	SetCookie(client, F_Cookies.finishDiffShowPrefix, CT_Boolean, F_Settings[client].finishDiffShowPrefix);
	SetCookie(client, F_Cookies.finishTimeEnabled, CT_Boolean, F_Settings[client].showFinishTime);
}

void ResetClientState(int client)
{
	T_Settings[client].showTime             = DEFAULT_SHOW_TIME;
	T_Settings[client].timePosition[AXIS_X] = POSITION_CENTER;
	T_Settings[client].timePosition[AXIS_Y] = DEFAULT_TIME_POSITION_Y;
	T_Settings[client].timePrecision        = DEFAULT_TIME_PRECISION;

	F_Settings[client].showFinishDiff = DEFAULT_FINISH_DIFF;
	F_Settings[client].finishDiffMode = DEFAULT_FINISH_DIFF_MODE;
	F_Settings[client].finishDiffPosition[AXIS_X] = DEFAULT_FINISH_DIFF_POSITION_X;
	F_Settings[client].finishDiffPosition[AXIS_Y] = DEFAULT_FINISH_DIFF_POSITION_Y;
	F_Settings[client].finishTimePositionX = DEFAULT_FINISH_TIME_POSITION_X;
	F_Settings[client].finishTimePositionY = DEFAULT_FINISH_TIME_POSITION_Y;
	F_Settings[client].finishDiffShowPrefix = DEFAULT_FINISH_DIFF_SHOW_PREFIX;
	F_Settings[client].showFinishTime = DEFAULT_FINISH_TIME;

	int color[3];
	for (int i = 0; i < view_as<int>(RGB_MAX); i++)
	{
		ApplyColorByNameRaw(g_RGBDefaults[i], color);
		SetRGBSettings(client, view_as<RGBType>(i), color);
	}

	gB_SettingAxis[client] = false;
	gB_InFinishDiffColorMenu[client] = false;
	gB_PreviewActive[client] = false;
	gH_PositionMenu[client] = null;
	g_PositionMenuSource[client] = HUD_TIME;
	g_PositionMenuOrigin[client] = HUD_TIME;
	g_CurrentRGBType[client] = RGB_INVALID;
	gF_Modifier[client] = 0.1;
	gF_LastRunTime[client] = 0.0;
	g_RGBStep[client] = 10;
}

/* ---- Time HUD Commands & Menus ---- */

public Action Command_TimeHUDMenu(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;

	OpenTimeHUDMenu(client);
	return Plugin_Handled;
}

void OpenTimeHUDMenu(int client)
{
	Menu menu = new Menu(TimeHUDMenu_Handler);
	menu.SetTitle("Time HUD Settings");

	char sInfo[128];
	char timeStr[32], practiceStr[32], startZoneStr[32], completionStr[32];

	GetColorDisplay(client, RGB_TIME, timeStr, sizeof(timeStr));
	GetColorDisplay(client, RGB_PRACTICE, practiceStr, sizeof(practiceStr));
	GetColorDisplay(client, RGB_STARTZONE, startZoneStr, sizeof(startZoneStr));
	GetColorDisplay(client, RGB_COMPLETION, completionStr, sizeof(completionStr));

	FormatEx(sInfo, sizeof(sInfo), "Enabled: [%s]", T_Settings[client].showTime ? "ON" : "OFF");
	menu.AddItem("toggle", sInfo);

	FormatEx(sInfo, sizeof(sInfo), "Decimal Places: %d", T_Settings[client].timePrecision);
	menu.AddItem("precision", sInfo);

	FormatEx(sInfo, sizeof(sInfo),
		"Color Settings\n    Default Color: %s\n    Practice Mode Color: %s\n    Start Zone Color: %s\n    Finish Color: %s",
		timeStr, practiceStr, startZoneStr, completionStr);
	menu.AddItem("colors", sInfo);

	FormatEx(sInfo, sizeof(sInfo), "Position Settings\n    Current: %.3f, %.3f",
		T_Settings[client].timePosition[AXIS_X], T_Settings[client].timePosition[AXIS_Y]);
	menu.AddItem("position", sInfo);

	menu.ExitBackButton = false;
	menu.Display(client, MENU_TIME_FOREVER);
}

int TimeHUDMenu_Handler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(item, info, sizeof(info));

		if (StrEqual(info, "toggle"))
		{
			T_Settings[client].showTime = !T_Settings[client].showTime;

			if (T_Settings[client].showTime && F_Settings[client].showFinishTime)
			{
				F_Settings[client].showFinishTime = false;
				SetCookie(client, F_Cookies.finishTimeEnabled, CT_Boolean, false);
				CPrintToChat(client, "{lightblue}[CenterTimer]{white} Show Finish Time has been disabled because {lime}Time HUD{white} was enabled.");
			}
		}
		else if (StrEqual(info, "precision"))
		{
			if (T_Settings[client].timePrecision == TIME_PRECISION_TENTH)
				T_Settings[client].timePrecision = TIME_PRECISION_HUNDREDTH;
			else if (T_Settings[client].timePrecision == TIME_PRECISION_HUNDREDTH)
				T_Settings[client].timePrecision = TIME_PRECISION_THOUSANDTH;
			else
				T_Settings[client].timePrecision = TIME_PRECISION_TENTH;
		}
		else if (StrEqual(info, "colors"))
		{
			OpenTimeColorMenu(client);
			return 0;
		}
		else if (StrEqual(info, "position"))
		{
			g_PositionMenuSource[client] = HUD_TIME;
			g_PositionMenuOrigin[client] = HUD_TIME;
			OpenPositionSettingsMenu(client);
			return 0;
		}

		OnCookieChangedTime(client);
		OpenTimeHUDMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void AddColorMenuItem(Menu menu, RGBType type, const char[] label)
{
	char sInfo[8];
	IntToString(view_as<int>(type), sInfo, sizeof(sInfo));
	menu.AddItem(sInfo, label);
}

void AddColorMenuEntry(Menu menu, int client, RGBType type, const char[] labelFmt)
{
	char sColor[32], sLabel[64];
	GetColorDisplay(client, type, sColor, sizeof(sColor));
	FormatEx(sLabel, sizeof(sLabel), labelFmt, sColor);
	AddColorMenuItem(menu, type, sLabel);
}

void OpenTimeColorMenu(int client)
{
	Menu menu = new Menu(TimeColorMenu_Handler);
	gB_InFinishDiffColorMenu[client] = false;

	menu.SetTitle("Time HUD Colors");
	AddColorMenuEntry(menu, client, RGB_TIME, "Default Color: %s");
	AddColorMenuEntry(menu, client, RGB_PRACTICE, "Practice Color: %s");
	AddColorMenuEntry(menu, client, RGB_STARTZONE, "Start Zone Color: %s");
	AddColorMenuEntry(menu, client, RGB_COMPLETION, "Finish Color: %s");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int TimeColorMenu_Handler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(item, sInfo, sizeof(sInfo));

		int type = StringToInt(sInfo);
		if (type >= 0 && type < view_as<int>(RGB_MAX))
			OpenPresetColorMenu(client, view_as<RGBType>(type));
	}
	else if (action == MenuAction_Cancel)
	{
		OpenTimeHUDMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

/* ---- Finish Diff Commands & Menus ---- */

public Action Command_FinishDiffMenu(int client, int args)
{
	if (client == 0)
		return Plugin_Handled;

	OpenFinishDiffMenu(client);

	// if (F_Settings[client].showFinishDiff)
	CPrintToChat(client, "{lightblue}[CenterTimer]{white} {red}WARNING{white}: {orange}Finish Diff HUD{white} may conflict with {orange}StrafeTrainer HUD{white}. Disable StrafeTrainer if issues occur.");

	return Plugin_Handled;
}

void GetFinishDiffModeName(FinishDiffMode mode, char[] buffer, int maxlen)
{
	if (mode == FINISH_DIFF_WR)
		strcopy(buffer, maxlen, "WR (SourceJump)");
	else if (mode == FINISH_DIFF_SR)
		strcopy(buffer, maxlen, "Server Record");
	else
		strcopy(buffer, maxlen, "Personal Best");
}

void OpenFinishDiffMenu(int client)
{
	Menu menu = new Menu(FinishDiffMenu_Handler);
	menu.SetTitle("Finish Diff Settings");

	char sInfo[128];
	char modeStr[32];
	char faster[32], slower[32];

	GetFinishDiffModeName(view_as<FinishDiffMode>(F_Settings[client].finishDiffMode), modeStr, sizeof(modeStr));
	GetColorDisplay(client, RGB_FINISH_FASTER, faster, sizeof(faster));
	GetColorDisplay(client, RGB_FINISH_SLOWER, slower, sizeof(slower));

	FormatEx(sInfo, sizeof(sInfo), "Enabled: [%s]", F_Settings[client].showFinishDiff ? "ON" : "OFF");
	menu.AddItem("toggle", sInfo);

	FormatEx(sInfo, sizeof(sInfo), "Compare: %s", modeStr);
	menu.AddItem("mode", sInfo);

	FormatEx(sInfo, sizeof(sInfo), "Show Prefix: [%s]", F_Settings[client].finishDiffShowPrefix ? "ON" : "OFF");
	menu.AddItem("prefix", sInfo);

	FormatEx(sInfo, sizeof(sInfo), "Show Finish Time: [%s]", F_Settings[client].showFinishTime ? "ON" : "OFF");
	menu.AddItem("finishtime", sInfo);

	FormatEx(sInfo, sizeof(sInfo), "Position Settings\n    Current: %.3f, %.3f",
		F_Settings[client].finishDiffPosition[AXIS_X], F_Settings[client].finishDiffPosition[AXIS_Y]);
	menu.AddItem("position", sInfo);

	FormatEx(sInfo, sizeof(sInfo), "Color Settings\n    Faster Color: %s\n    Slower Color: %s", faster, slower);
	menu.AddItem("colors", sInfo);

	menu.ExitBackButton = false;
	menu.Display(client, MENU_TIME_FOREVER);
}

int FinishDiffMenu_Handler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(item, info, sizeof(info));

		if (StrEqual(info, "toggle"))
		{
			F_Settings[client].showFinishDiff = !F_Settings[client].showFinishDiff;

			if (F_Settings[client].showFinishDiff)
				CPrintToChat(client, "{lightblue}[CenterTimer]{white} {red}WARNING{white}: {orange}Finish Diff HUD{white} may conflict with {orange}StrafeTrainer HUD{white}. Disable StrafeTrainer if issues occur.");
		}
		else if (StrEqual(info, "mode"))
		{
			F_Settings[client].finishDiffMode++;
			if (F_Settings[client].finishDiffMode > view_as<int>(FINISH_DIFF_PB))
				F_Settings[client].finishDiffMode = FINISH_DIFF_WR;
		}
		else if (StrEqual(info, "prefix"))
		{
			F_Settings[client].finishDiffShowPrefix = !F_Settings[client].finishDiffShowPrefix;
		}
		else if (StrEqual(info, "position"))
		{
			g_PositionMenuSource[client] = HUD_FINISH;
			g_PositionMenuOrigin[client] = HUD_FINISH;
			OpenPositionSettingsMenu(client);
			return 0;
		}
		else if (StrEqual(info, "finishtime"))
		{
			F_Settings[client].showFinishTime = !F_Settings[client].showFinishTime;

			if (F_Settings[client].showFinishTime && T_Settings[client].showTime)
			{
				T_Settings[client].showTime = false;
				SetCookie(client, T_Cookies.showTime, CT_Boolean, false);
				CPrintToChat(client, "{lightblue}[CenterTimer]{white} Time HUD has been disabled because {lime}Show Finish Time{white} was enabled.");
			}
		}
		else if (StrEqual(info, "colors"))
		{
			OpenFinishDiffColorMenu(client);
			return 0;
		}

		OnCookieChangedFinishDiff(client);
		OpenFinishDiffMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenFinishDiffColorMenu(int client)
{
	Menu menu = new Menu(FinishDiffColorMenu_Handler);
	gB_InFinishDiffColorMenu[client] = true;

	menu.SetTitle("Finish Diff Colors");
	AddColorMenuEntry(menu, client, RGB_FINISH_FASTER, "Faster Color: %s");
	AddColorMenuEntry(menu, client, RGB_FINISH_SLOWER, "Slower Color: %s");
	AddColorMenuEntry(menu, client, RGB_COMPLETION, "Finish Time Color: %s");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int FinishDiffColorMenu_Handler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(item, sInfo, sizeof(sInfo));

		int type = StringToInt(sInfo);
		if (type >= 0 && type < view_as<int>(RGB_MAX))
			OpenPresetColorMenu(client, view_as<RGBType>(type));
	}
	else if (action == MenuAction_Cancel)
	{
		OpenFinishDiffMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

/* ---- Shared Position Menu ---- */

void OpenPositionSettingsMenu(int client)
{
	Menu hMenu = new Menu(PositionSettingsMenu_Handler);
	HUDType source = g_PositionMenuSource[client];

	float posX = GetHudPosition(client, source, AXIS_X);
	float posY = GetHudPosition(client, source, AXIS_Y);

	hMenu.SetTitle(
		"Position Settings\nCurrent Position: (%.3f, %.3f)\n ",
		posX, posY);

	char sInfo[33];
	FormatEx(sInfo, sizeof(sInfo), "Target: %s\n ", source == HUD_FINISH ? "Finish Diff" : "Time HUD");
	hMenu.AddItem("target", sInfo);
	FormatEx(sInfo, sizeof(sInfo), "Axis: %s", gB_SettingAxis[client] ? "X" : "Y");
	hMenu.AddItem("axis", sInfo);
	FormatEx(sInfo, sizeof(sInfo), "Step: %d\n ", RoundToFloor(gF_Modifier[client] * 1000.0));
	hMenu.AddItem("modifier", sInfo);
	FormatEx(sInfo, sizeof(sInfo), "+%d", RoundToFloor(gF_Modifier[client] * 1000.0));
	hMenu.AddItem("+", sInfo);
	FormatEx(sInfo, sizeof(sInfo), "-%d\n ", RoundToFloor(gF_Modifier[client] * 1000.0));
	hMenu.AddItem("-", sInfo);
	hMenu.AddItem("center", "Center");
	hMenu.AddItem("default", "Default");

	hMenu.ExitBackButton = true;
	gH_PositionMenu[client] = hMenu;
	gB_PreviewActive[client] = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
	DrawPositionPreview(client);
}

int PositionSettingsMenu_Handler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(item, sInfo, sizeof(sInfo));

		HUDType source = g_PositionMenuSource[client];
		int iAxis = gB_SettingAxis[client] ? AXIS_X : AXIS_Y;

		if (StrEqual(sInfo, "target"))
			g_PositionMenuSource[client] = (g_PositionMenuSource[client] == HUD_TIME) ? HUD_FINISH : HUD_TIME;
		else if (StrEqual(sInfo, "axis"))
			gB_SettingAxis[client] = !gB_SettingAxis[client];
		else if (StrEqual(sInfo, "modifier"))
			gF_Modifier[client] = gF_Modifier[client] == 0.1 ? 0.01 : gF_Modifier[client] == 0.01 ? 0.001 : 0.1;
		else if (StrEqual(sInfo, "center"))
			SetHudPosition(client, source, iAxis, POSITION_CENTER);
		else if (StrEqual(sInfo, "default"))
			ResetHudPosition(client, source);
		else if (StrEqual(sInfo, "+"))
			AddOrMinusPosition(client, source, iAxis, gF_Modifier[client], true);
		else if (StrEqual(sInfo, "-"))
			AddOrMinusPosition(client, source, iAxis, gF_Modifier[client], false);

		OpenPositionSettingsMenu(client);
	}
	else if (action == MenuAction_Cancel)
	{
		gB_PreviewActive[client] = false;

		if (g_PositionMenuOrigin[client] == HUD_FINISH)
			OpenFinishDiffMenu(client);
		else
			OpenTimeHUDMenu(client);
	}
	else if (action == MenuAction_End)
	{
		if (client > 0 && gH_PositionMenu[client] == menu)
		{
			gB_PreviewActive[client] = false;
			gH_PositionMenu[client] = null;
		}

		delete menu;
	}

	return 0;
}

void AddOrMinusPosition(int client, HUDType source, int axis, float value, bool add)
{
	float current = GetHudPosition(client, source, axis);

	if (current == POSITION_CENTER)
	{
		SetHudPosition(client, source, axis, add ? 0.49 : 0.50);
		return;
	}

	current += add ? value : -value;
	if (current > 1.0)
		current = 1.0;
	else if (current < 0.0)
		current = 0.0;

	SetHudPosition(client, source, axis, current);
}

float GetHudPosition(int client, HUDType source, int axis)
{
	return source == HUD_FINISH
		? F_Settings[client].finishDiffPosition[axis]
		: T_Settings[client].timePosition[axis];
}

void SetHudPosition(int client, HUDType source, int axis, float value)
{
	Cookie cookie;

	if (source == HUD_FINISH)
	{
		F_Settings[client].finishDiffPosition[axis] = value;
		cookie = (axis == AXIS_X) ? F_Cookies.finishDiffPositionX : F_Cookies.finishDiffPositionY;
	}
	else
	{
		T_Settings[client].timePosition[axis] = value;
		cookie = (axis == AXIS_X) ? T_Cookies.timePositionX : T_Cookies.timePositionY;
	}

	SetCookie(client, cookie, CT_Float, value);
}

void ResetHudPosition(int client, HUDType source)
{
	SetHudPosition(client, source, AXIS_X, POSITION_CENTER);
	SetHudPosition(client, source, AXIS_Y,
		source == HUD_FINISH ? DEFAULT_FINISH_DIFF_POSITION_Y : DEFAULT_TIME_POSITION_Y);
}

public Action Timer_PositionPreview(Handle timer)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!gB_PreviewActive[client])
			continue;

		if (!IsClientInGame(client) || IsFakeClient(client))
		{
			gB_PreviewActive[client] = false;
			continue;
		}

		DrawPositionPreview(client);
	}

	return Plugin_Continue;
}

void DrawPositionPreview(int client)
{
	bool bTimeActive = (g_PositionMenuSource[client] == HUD_TIME);

	// Time HUD marker, on the same channel as the live timer HUD.
	float posX = T_Settings[client].timePosition[AXIS_X];
	float posY = T_Settings[client].timePosition[AXIS_Y];

	char sTime[16], sText[32];
	FormatTimerWithPrecision(0.0, sTime, sizeof(sTime), T_Settings[client].timePrecision);
	FormatEx(sText, sizeof(sText), "TIME [%s]", sTime);

	SetHudTextParams(posX, posY, 0.5, 255, bTimeActive ? 255 : 80, bTimeActive ? 0 : 80,
		255, 0, 0.0, 0.0, 0.0);
	ShowHudText(client, GetDynamicChannel(3), "%s", sText);

	// Finish Diff marker, on the same synchronizer as the real finish diff.
	posX = F_Settings[client].finishDiffPosition[AXIS_X];
	posY = F_Settings[client].finishDiffPosition[AXIS_Y];

	char sPrefix[4];
	switch (F_Settings[client].finishDiffMode)
	{
		case FINISH_DIFF_WR: strcopy(sPrefix, sizeof(sPrefix), "WR");
		case FINISH_DIFF_SR: strcopy(sPrefix, sizeof(sPrefix), "SR");
		default:             strcopy(sPrefix, sizeof(sPrefix), "PB");
	}

	if (F_Settings[client].finishDiffShowPrefix)
		FormatEx(sText, sizeof(sText), "DIFF [%s: +0.000]", sPrefix);
	else
		strcopy(sText, sizeof(sText), "DIFF [+0.000]");

	SetHudTextParams(posX, posY, 0.5, 255, bTimeActive ? 80 : 255, bTimeActive ? 80 : 0,
		255, 0, 0.0, 0.0, 0.0);
	ShowSyncHudText(client, gH_SyncFinishDiff, "%s", sText);
}

/* ---- Shared Preset Color Menu ---- */

void OpenPresetColorMenu(int client, RGBType type)
{
	g_CurrentRGBType[client] = type;

	Menu menu = new Menu(PresetColor_Handler);

	char sCurrent[32], sTypeName[32];
	GetColorDisplay(client, type, sCurrent, sizeof(sCurrent));
	GetRGBTypeName(type, sTypeName, sizeof(sTypeName));

	char sTitle[96];
	FormatEx(sTitle, sizeof(sTitle), "Select Color\n%s : %s", sTypeName, sCurrent);
	menu.SetTitle("%s", sTitle);

	char sInfo[8];
	IntToString(view_as<int>(type), sInfo, sizeof(sInfo));

	menu.AddItem(sInfo, "Custom RGB");
	for (int i = 0; i < sizeof(g_ColorNames); i++)
		menu.AddItem(sInfo, g_ColorNames[i]);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int PresetColor_Handler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char sInfo[8], sColor[16];
		menu.GetItem(item, sInfo, sizeof(sInfo), _, sColor, sizeof(sColor));

		int type = StringToInt(sInfo);
		if (type < 0 || type >= view_as<int>(RGB_MAX))
			return 0;

		RGBType rgbType = view_as<RGBType>(type);
		g_CurrentRGBType[client] = rgbType;

		if (StrEqual(sColor, "Custom RGB"))
		{
			OpenCustomRGBMenu(client, rgbType);
			return 0;
		}

		ApplyColorByName(sColor, client, rgbType);
		SaveColorChoiceToCookie(client, rgbType, sColor);
		OpenPresetColorMenu(client, rgbType);
	}
	else if (action == MenuAction_Cancel)
	{
		GoBackFromColorMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

/* ---- Shared Custom RGB Menu ---- */

void OpenCustomRGBMenu(int client, RGBType type)
{
	RGBType rgbType = (type >= RGB_TIME && type < RGB_MAX) ? type : g_CurrentRGBType[client];
	if (rgbType < RGB_TIME || rgbType >= RGB_MAX)
		return;

	g_CurrentRGBType[client] = rgbType;

	if (g_RGBStep[client] <= 0)
		g_RGBStep[client] = 10;

	int color[3];
	char sTypeName[32];
	GetRGBSettings(client, rgbType, color);
	GetRGBTypeName(rgbType, sTypeName, sizeof(sTypeName));

	Menu menu = new Menu(CustomRGB_Handler);
	char sTitle[128];
	Format(sTitle, sizeof(sTitle),
		"=== RGB Editor ===\nMode: %s\nStep: %d\n \nCurrent: %d %d %d\n ",
		sTypeName, g_RGBStep[client], color[0], color[1], color[2]);
	menu.SetTitle("%s", sTitle);

	menu.AddItem("r_plus", "Red +");
	menu.AddItem("r_minus", "Red -");
	menu.AddItem("g_plus", "Green +");
	menu.AddItem("g_minus", "Green -");
	menu.AddItem("b_plus", "Blue +");
	menu.AddItem("b_minus", "Blue - \n ");
	menu.AddItem("step", "Switch Step");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int CustomRGB_Handler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(item, info, sizeof(info));

		if (StrEqual(info, "step"))
		{
			if (g_RGBStep[client] == 1)
				g_RGBStep[client] = 10;
			else if (g_RGBStep[client] == 10)
				g_RGBStep[client] = 100;
			else
				g_RGBStep[client] = 1;

			OpenCustomRGBMenu(client, g_CurrentRGBType[client]);
			return 0;
		}

		AdjustCustomRGBColor(client, g_CurrentRGBType[client], info, g_RGBStep[client]);
		OpenCustomRGBMenu(client, g_CurrentRGBType[client]);
	}
	else if (action == MenuAction_Cancel)
	{
		OpenPresetColorMenu(client, g_CurrentRGBType[client]);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void GoBackFromColorMenu(int client)
{
	if (gB_InFinishDiffColorMenu[client])
		OpenFinishDiffColorMenu(client);
	else
		OpenTimeColorMenu(client);
}

/* ---- HUD Draw ---- */

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3],
		float angles[3], int &weapon, int &subtype, int &cmdnum,
		int &tickcount, int &seed, int mouse[2])
{
	// Cheap checks first: the HUD is off for most clients and only redrawn
	// every N usercmds, so skip all native calls on the other commands.
	if (!T_Settings[client].showTime || cmdnum % TIME_HUD_CMD_INTERVAL != 0)
		return Plugin_Continue;

	if (!IsValidClient(client) || IsFakeClient(client))
		return Plugin_Continue;

	// Hide the live timer while the position previews are on screen.
	if (gB_PreviewActive[client])
		return Plugin_Continue;

	DrawTimerHUD(client, GetSpectatorTarget(client, client));
	return Plugin_Continue;
}

void DrawTimerHUD(int client, int target)
{
	bool bReplay = false;

	// Replay entities are either fake clients or props; only they need the
	// (relatively expensive) replay check. Regular players skip it entirely.
	if (gB_ReplayPlayback && (!IsValidClient(target) || IsFakeClient(target)) && Shavit_IsReplayEntity(target))
	{
		bReplay = true;
	}
	else if (!IsValidClient(target))
	{
		return;
	}

	float fTime = bReplay ? Shavit_GetReplayTime(target) : Shavit_GetClientTime(target);

	int iColor[3];
	iColor = T_Settings[client].colorTime;

	if (!bReplay)
	{
		bool bInStart = Shavit_InsideZone(target, Zone_Start, Shavit_GetClientTrack(target));

		if (bInStart)
		{
			iColor = T_Settings[client].colorTimeInStartZone;
		}
		else if (Shavit_IsPracticeMode(target))
		{
			iColor = T_Settings[client].colorTimeInPractice;
		}

		// Completion state belongs to the player being watched, not the spectator.
		if (!bInStart && gF_LastRunTime[target] > 0.0 && fTime <= 0.0)
		{
			iColor = T_Settings[client].colorTimeCompletion;
			fTime = gF_LastRunTime[target];
		}
	}

	SetHudTextParams(
		T_Settings[client].timePosition[AXIS_X], T_Settings[client].timePosition[AXIS_Y],
		0.35, iColor[0], iColor[1], iColor[2], 255, 0, 1.0, 0.0, 0.0);

	char sBuffer[HUD_BUF_SIZE];
	FormatTimerWithPrecision(fTime, sBuffer, sizeof(sBuffer), T_Settings[client].timePrecision);
	ShowHudText(client, GetDynamicChannel(3), "%s", sBuffer);
}

void DrawFinishDiffHUD(int client, int style, float time, float oldtime, int track)
{
	if (!IsValidClient(client) || IsFakeClient(client) || !F_Settings[client].showFinishDiff)
		return;

	char sPrefix[4];
	float fRef;
	bool bHas;

	switch (F_Settings[client].finishDiffMode)
	{
		case FINISH_DIFF_WR:
		{
			bHas = (track == Track_Main && g_fWRTime > 0.0);
			fRef = g_fWRTime;
			strcopy(sPrefix, sizeof(sPrefix), "WR");
		}
		case FINISH_DIFF_SR:
		{
			fRef = Shavit_GetTimeForRank(style, 1, track);
			bHas = fRef > 0.0;
			strcopy(sPrefix, sizeof(sPrefix), "SR");
		}
		case FINISH_DIFF_PB:
		{
			fRef = oldtime;
			bHas = oldtime > 0.0;
			strcopy(sPrefix, sizeof(sPrefix), "PB");
		}
		default:
		{
			return;
		}
	}

	bool bShowPrefix = F_Settings[client].finishDiffShowPrefix;
	char sLabel[64];
	float fDiff = 0.0;

	if (!bHas)
	{
		Format(sLabel, sizeof(sLabel), bShowPrefix ? "%s: N/A" : "N/A", sPrefix);
	}
	else
	{
		fDiff = time - fRef;

		char sDiff[32];
		if (fDiff >= 0.0)
		{
			sDiff[0] = '+';
			FormatTimerWithPrecision(fDiff, sDiff[1], sizeof(sDiff) - 1, TIME_PRECISION_THOUSANDTH);
		}
		else
		{
			FormatTimerWithPrecision(fDiff, sDiff, sizeof(sDiff), TIME_PRECISION_THOUSANDTH);
		}

		if (bShowPrefix)
			Format(sLabel, sizeof(sLabel), "%s: %s", sPrefix, sDiff);
		else
			Format(sLabel, sizeof(sLabel), "%s", sDiff);
	}

	int r, g, b;
	if (fDiff <= 0.0)
	{
		r = F_Settings[client].finishDiffColorFaster[0];
		g = F_Settings[client].finishDiffColorFaster[1];
		b = F_Settings[client].finishDiffColorFaster[2];
	}
	else
	{
		r = F_Settings[client].finishDiffColorSlower[0];
		g = F_Settings[client].finishDiffColorSlower[1];
		b = F_Settings[client].finishDiffColorSlower[2];
	}

	SetHudTextParams(F_Settings[client].finishDiffPosition[AXIS_X], F_Settings[client].finishDiffPosition[AXIS_Y],
		1.5, r, g, b, 255, 0, 0.0, 0.3, 0.3);
	ShowSyncHudText(client, gH_SyncFinishDiff, "%s", sLabel);
	// ShowHudText(client, GetDynamicChannel(3), "%s", sLabel);
}

void DrawFinishTimeHUD(int client, float time)
{
	if (!IsValidClient(client) || IsFakeClient(client) || !F_Settings[client].showFinishTime)
		return;

	if (time <= 0.0)
		return;

	char buffer[HUD_BUF_SIZE];
	FormatTimerWithPrecision(time, buffer, sizeof(buffer), TIME_PRECISION_THOUSANDTH);

	SetHudTextParams(
		F_Settings[client].finishTimePositionX,
		F_Settings[client].finishTimePositionY,
		1.5,
		T_Settings[client].colorTimeCompletion[0],
		T_Settings[client].colorTimeCompletion[1],
		T_Settings[client].colorTimeCompletion[2],
		255, 0, 0.0, 0.3, 0.3);

	ShowSyncHudText(client, gH_SyncFinishTime, "%s", buffer);
	// ShowHudText(client, GetDynamicChannel(3), "%s", buffer);
}

void FormatTimerWithPrecision(float fTime, char[] buffer, int maxlen, int precision)
{
	if (precision < TIME_PRECISION_TENTH || precision > TIME_PRECISION_THOUSANDTH)
		precision = DEFAULT_TIME_PRECISION;

	static const int s_Factors[] = { 1, 10, 100, 1000 };
	int factor = s_Factors[precision];

	bool bNegative = (fTime < 0.0);
	float fAbsTime = bNegative ? -fTime : fTime;
	int iTime = RoundToFloor(fAbsTime * float(factor));
	int iMinutes = iTime / (60 * factor);
	int iSeconds = (iTime / factor) % 60;
	int iFraction = iTime % factor;

	char sSign[2];
	if (bNegative)
		sSign[0] = '-';

	static const char s_Formats[3][2][24] =
	{
		{ "%s%d.%d",   "%s%d:%02d.%d" },
		{ "%s%d.%02d", "%s%d:%02d.%02d" },
		{ "%s%d.%03d", "%s%d:%02d.%03d" }
	};

	if (iMinutes > 0)
		Format(buffer, maxlen, s_Formats[precision - 1][1], sSign, iMinutes, iSeconds, iFraction);
	else
		Format(buffer, maxlen, s_Formats[precision - 1][0], sSign, iSeconds, iFraction);
}

/* ---- Shared Helpers ---- */

void GetColorDisplay(int client, RGBType type, char[] buffer, int maxlen)
{
	if (type < RGB_TIME || type >= RGB_MAX)
	{
		strcopy(buffer, maxlen, "Default");
		return;
	}

	char value[32];
	Cookie cookie = GetColorCookie(type);
	cookie.Get(client, value, sizeof(value));

	if (value[0] == '\0')
		strcopy(buffer, maxlen, "Default");
	else
		strcopy(buffer, maxlen, value);
}

Cookie GetColorCookie(RGBType type)
{
	switch (type)
	{
		case RGB_TIME:          return T_Cookies.colorTime;
		case RGB_PRACTICE:      return T_Cookies.colorTimeInPractice;
		case RGB_STARTZONE:     return T_Cookies.colorTimeInStartZone;
		case RGB_COMPLETION:    return T_Cookies.colorTimeCompletion;
		case RGB_FINISH_FASTER: return F_Cookies.colorFinishFaster;
		case RGB_FINISH_SLOWER: return F_Cookies.colorFinishSlower;
	}

	return null;
}

void GetRGBTypeName(RGBType type, char[] name, int maxlen)
{
	if (type < RGB_TIME || type >= RGB_MAX)
	{
		strcopy(name, maxlen, "Unknown Color");
		return;
	}

	strcopy(name, maxlen, g_RGBTypeNames[view_as<int>(type)]);
}

void GetRGBSettings(int client, RGBType type, int color[3])
{
	switch (type)
	{
		case RGB_TIME:          color = T_Settings[client].colorTime;
		case RGB_PRACTICE:      color = T_Settings[client].colorTimeInPractice;
		case RGB_STARTZONE:     color = T_Settings[client].colorTimeInStartZone;
		case RGB_COMPLETION:    color = T_Settings[client].colorTimeCompletion;
		case RGB_FINISH_FASTER: color = F_Settings[client].finishDiffColorFaster;
		case RGB_FINISH_SLOWER: color = F_Settings[client].finishDiffColorSlower;
		default:                color[0] = color[1] = color[2] = 255;
	}
}

void SetRGBSettings(int client, RGBType type, int color[3])
{
	switch (type)
	{
		case RGB_TIME:          T_Settings[client].colorTime = color;
		case RGB_PRACTICE:      T_Settings[client].colorTimeInPractice = color;
		case RGB_STARTZONE:     T_Settings[client].colorTimeInStartZone = color;
		case RGB_COMPLETION:    T_Settings[client].colorTimeCompletion = color;
		case RGB_FINISH_FASTER: F_Settings[client].finishDiffColorFaster = color;
		case RGB_FINISH_SLOWER: F_Settings[client].finishDiffColorSlower = color;
	}
}

void ApplyColorByName(const char[] value, int client, RGBType type)
{
	int color[3];
	ApplyColorByNameRaw(value, color);
	SetRGBSettings(client, type, color);
}

void ApplyColorByNameRaw(const char[] value, int color[3])
{
	if (StrContains(value, " ") != -1)
	{
		char parts[3][8];
		ExplodeString(value, " ", parts, 3, 8);
		color[0] = StringToInt(parts[0]);
		color[1] = StringToInt(parts[1]);
		color[2] = StringToInt(parts[2]);
		return;
	}

	for (int i = 0; i < sizeof(g_ColorNames); i++)
	{
		if (StrEqual(value, g_ColorNames[i]))
		{
			color[0] = g_ColorValues[i][0];
			color[1] = g_ColorValues[i][1];
			color[2] = g_ColorValues[i][2];
			return;
		}
	}

	color[0] = 255;
	color[1] = 255;
	color[2] = 255;
}

void AdjustCustomRGBColor(int client, RGBType type, const char[] info, int delta)
{
	if (type < RGB_TIME || type >= RGB_MAX)
		return;

	int color[3];
	GetRGBSettings(client, type, color);
	AdjustRGBColorValues(color, info, delta);
	SetRGBSettings(client, type, color);
	SaveColorToCookie(client, type, color);
}

void AdjustRGBColorValues(int color[3], const char[] info, int delta)
{
	if (StrEqual(info, "r_plus"))
		AdjustColorValue(color, 0, delta);
	else if (StrEqual(info, "r_minus"))
		AdjustColorValue(color, 0, -delta);
	else if (StrEqual(info, "g_plus"))
		AdjustColorValue(color, 1, delta);
	else if (StrEqual(info, "g_minus"))
		AdjustColorValue(color, 1, -delta);
	else if (StrEqual(info, "b_plus"))
		AdjustColorValue(color, 2, delta);
	else if (StrEqual(info, "b_minus"))
		AdjustColorValue(color, 2, -delta);
}

void AdjustColorValue(int color[3], int index, int delta)
{
	color[index] += delta;

	if (color[index] < 0)
		color[index] = 0;
	else if (color[index] > 255)
		color[index] = 255;
}

void SaveColorToCookie(int client, RGBType type, int color[3])
{
	Cookie cookie = GetColorCookie(type);
	if (cookie == null)
		return;

	char buffer[32];
	Format(buffer, sizeof(buffer), "%d %d %d", color[0], color[1], color[2]);
	cookie.Set(client, buffer);
}

void SaveColorChoiceToCookie(int client, RGBType type, const char[] choice)
{
	Cookie cookie = GetColorCookie(type);
	if (cookie != null)
		cookie.Set(client, choice);
}
