/*
 * Empire, the Wargame of the Century (tm)
 * Copyright (C) 1978-2004 by Walter Bright
 * All Rights Reserved
 * www.classicempire.com
 *
 * You may use this source for personal use only. To use it commercially
 * or to distribute source or binaries of Empire, please contact
 * www.digitalmars.com.
 *
 * Written by Walter Bright.
 * Modified by Stewart Gordon.
 * This source is written in the D Programming Language.
 * See www.digitalmars.com/d/ for the D specification and compiler.
 *
 * Use entirely at your own risk. There is no warranty, expressed or implied.
 */

module winmain;
import core.stdc.stdlib;
import core.stdc.stdio;
import core.sys.windows.windows;
import std.math;
import std.string;
import std.conv;

import empire;
import winemp;
import eplayer;
version(NewDisplay) {
	import newdisplay;
} else {
	import display;
	import text;
	import core.stdc.string;	// for strlen
}
import twin;
import init;
import move;
import var;
import maps;

/********************************************************/
extern (C) void gc_init();
extern (C) void gc_term();
extern (C) void _minit();
extern (C) void _moduleCtor();
//extern (C) void _moduleUnitTests();
extern (Windows) BOOL DestroyWindow(HWND hWnd);

extern (Windows)
int WinMain(HINSTANCE hInstance,
	HINSTANCE hPrevInstance,
	LPSTR lpCmdLine,
	int nCmdShow)
{
	int result;

	gc_init();			// initialize garbage collector
	_minit();			// initialize module constructor table

	try
	{
		_moduleCtor();		// call module constructors
		//_moduleUnitTests();	// run unit tests (optional)

		// insert user code here
		result = doit(hInstance, hPrevInstance, lpCmdLine, nCmdShow);
	}
	catch (Throwable o)		// catch any uncaught exceptions
	{
		MessageBoxA(null, cast(char*) o.toString(), "Error",
				MB_OK | MB_ICONEXCLAMATION);
		result = 0;		// failed
	}

	gc_term();			// run finalizers; terminate garbage collector
	return result;
}
/********************************************************/


/* Collect all Windows static global data.
 */

struct Global
{
	HANDLE hinst;	// instance of entire program program
	HWND hwnd;		// handle of main window

	int inited;		// !=0 means game is initialized
	HANDLE hSplash;	// handle for splash screen .bmp

	// City Select
	int phase;
	int newphase;

	// Init
	int numplayers;
	int newnumplayers;
	int demo;

	int speaker;	// !=0 means sound is on

	// Menu
	HMENU hMenu;

	OPENFILENAMEA ofn;	// open file
	OPENFILENAMEA sfn;	// save file

	double scalex;	// zoom factor
	double scaley;	// zoom factor

	// Font
	HFONT  hFont;
	int cxChar, cxCaps, cyChar;

	// Pen
	//HPEN borderPen;
	HPEN dashedPen;
	HPEN originalPen;

	// Bitmaps
	HANDLE[MAPMAX] mapvaltab;
	HANDLE unknown10;

	Player* player; // which player is being displayed
	ubyte* map;     // which map is being displayed
	loc_t ulcorner; // upper left corner
	loc_t cursor;   // location of cursor
	HANDLE hCursor; // bitmap of cursor
	int offsetx;
	int offsety;

	// Window size
	int cxClient, cyClient;

	// Clipping rectangles
	RECT sector;
	RECT text;

	HRGN sectorRegion;
	HRGN textRegion;

	// Sector size
	int pixelx;
	int pixely;

	// Blast
	HANDLE hBlast;      // bitmap of blast
	HANDLE hBlastmask;  // bitmap of blast
	int blastState;     // !=0 means draw blast
	int blastx;
	int blasty;         // location of blast

	bool dirty;          // game state has changed since save?
	char bufferedKey;   // buffered gameplay keystroke
}

Global global;


int doit(HANDLE hInstance, HANDLE hPrevInstance,
					LPSTR lpszCmdLine, int nCmdShow)
{
	string szAppName = "Empire";
	HWND     hwnd;
	MSG      msg;
	WNDCLASSA wndclass;

	if (!hPrevInstance)
	{
		wndclass.style         = CS_HREDRAW | CS_VREDRAW;
		wndclass.lpfnWndProc   = &WndProc;
		wndclass.cbClsExtra    = 0;
		wndclass.cbWndExtra    = 0;
		wndclass.hInstance     = hInstance;
		wndclass.hIcon         = LoadIconA(hInstance, "About");
		wndclass.hCursor       = LoadCursor(null, IDC_ARROW);
		wndclass.hbrBackground = GetStockObject (WHITE_BRUSH);
		wndclass.lpszMenuName  = szAppName.ptr;
		wndclass.lpszClassName = szAppName.ptr;

		RegisterClassA(&wndclass);

		helpRegister(hInstance);
	}

	global.hinst = hInstance;

	version(none)
	{
		hwnd = CreateWindowA(szAppName.ptr, "Empire: Wargame of the Century",
				WS_OVERLAPPEDWINDOW,
				CW_USEDEFAULT, CW_USEDEFAULT,
				124, 160 + 34 + 20,
				null, null, hInstance, null);
	}
	else
	{
		hwnd = CreateWindowA(szAppName.ptr, "Empire: Wargame of the Century",
				WS_OVERLAPPEDWINDOW,
				CW_USEDEFAULT, CW_USEDEFAULT,
				CW_USEDEFAULT, CW_USEDEFAULT,
				null, null, hInstance, null);
	}

	ShowWindow(hwnd, nCmdShow);
	UpdateWindow(hwnd);

	while (true)
	{
		if (PeekMessageA(&msg, null, 0, 0, PM_REMOVE))
		{
			if (msg.message == WM_QUIT)
				break;
			TranslateMessage (&msg);
			DispatchMessageA (&msg);
		}
		else
		{
			// idle processing
			if (global.inited)
				slice();
			//invalidateLoc(global.cursor);
		}
	}
	return msg.wParam;
}

void DrawBitmap(HDC hdc, short xStart, short yStart, HBITMAP hBitmap,
  double scalex, double scaley, DWORD mode)
{
	// Petzold pg. 631 has a different version

	BITMAP bm;
	HDC    hMemDC;
	POINT  pt;

	//PRINTF("scalex = %g, scaley = %g\n", scalex, scaley);
	hMemDC = CreateCompatibleDC(hdc);
	SelectObject(hMemDC, hBitmap);
	GetObjectA(hBitmap, BITMAP.sizeof, cast(LPSTR) &bm);
	pt.x = bm.bmWidth;
	pt.y = bm.bmHeight;

	//BitBlt (hdc, xStart, yStart, pt.x, pt.y, hMemDC, 0, 0, mode);
	StretchBlt(hdc, xStart, yStart,
		cast(int) (pt.x * scalex + .99), cast(int) (pt.y * scaley + .99),
		hMemDC, 0, 0, pt.x, pt.y, mode);

	DeleteDC(hMemDC);
}

extern (Windows) int WndProc(HWND hwnd, uint message, WPARAM wParam,
					         LPARAM lParam) nothrow
{
	HANDLE		hBitmap;
	HDC			hdc;
	PAINTSTRUCT	ps;
	POINT		point;
	TEXTMETRICA	tm;
	int i;
	int j;
	int ch;
	static LOGFONTA logfont;
	double newscalex;
	double newscaley;

	// File dialog box
	static char[MAX_PATH] szFileName;
	static char[MAX_PATH] szTitleName;
	static string[] szFilter = [ "Empire Files (*.EMP)", "*.emp", "" ];

	try {
		switch (message)
		{
			case WM_CREATE:
			global.speaker = 1;

			global.cxClient = 120;
			global.cyClient = 160;

			global.pixelx = 120;
			global.pixely = 120;

			global.hwnd = hwnd;
			global.scalex = 1.0;
			global.scaley = 1.0;
			global.numplayers = IDD_FOUR;
			global.map = .map.ptr;
			global.offsetx = 0;
			global.offsety = 0;

			// Clipping rectangles
			global.text.left = 0;
			global.text.top = 0;
			global.text.right = global.pixelx;
			global.text.bottom = 40;

			global.sector.left = 0;
			global.sector.top = 40;
			global.sector.right = global.pixelx;
			global.sector.bottom = global.sector.top + global.pixely;

			global.sectorRegion = CreateRectRgn(global.sector.left, global.sector.top, global.sector.right, global.sector.bottom);
			global.textRegion = CreateRectRgn(global.text.left, global.text.top, global.text.right, global.text.bottom);

			// About dialog box
			//hInstance = ((LPCREATESTRUCT) lParam)->hInstance;

			// Menu
			global.hMenu = LoadMenuA(global.hinst, "PopMenu");
			global.hMenu = GetSubMenu(global.hMenu, 0);

			// File dialog box
			global.ofn.lStructSize       = OPENFILENAMEA.sizeof;
			global.ofn.hwndOwner         = hwnd;
			global.ofn.lpstrFilter       = szFilter[0].ptr;
			global.ofn.lpstrFile         = szFileName.ptr;
			global.ofn.nMaxFile          = MAX_PATH;
			global.ofn.lpstrFileTitle    = szTitleName.ptr;
			global.ofn.nMaxFileTitle     = MAX_PATH;
			global.ofn.lpstrDefExt       = "emp";

			szFileName[] = '\0';
			szTitleName[] = '\0';

			global.ofn.Flags = 0x00001000;
			// OFN_FILEMUSTEXIST

			global.sfn = global.ofn;
			global.sfn.Flags = 0x00000806;
			// OFN_HIDEREADONLY | OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT

			for (i = 0; i < MAPMAX; i++)
			{
				hBitmap = LoadBitmapA(global.hinst, MAKEINTRESOURCEA(i + 1));
				global.mapvaltab[i] = hBitmap;
			}
			global.unknown10 = LoadBitmapA(global.hinst, MAKEINTRESOURCEA(BMP_UNKNOWN10));
			global.hCursor = LoadBitmapA(global.hinst, MAKEINTRESOURCEA(BMP_CURSOR));
			global.hSplash = LoadBitmapA(global.hinst, MAKEINTRESOURCEA(BMP_SPLASH));
			global.hBlast = LoadBitmapA(global.hinst, MAKEINTRESOURCEA(BMP_BLAST));
			global.hBlastmask = LoadBitmapA(global.hinst, MAKEINTRESOURCEA(BMP_BLASTMASK));

			hdc = GetDC(hwnd);

			//global.borderPen = CreatePen(PS_SOLID, dx/3+2, RGB(255, 0, 0));
			global.dashedPen = CreatePen(PS_DASH, 0, RGB(255, 255, 255));
			global.originalPen = SelectObject(hdc, global.dashedPen);

			logfont.lfHeight = 10;
			logfont.lfWidth = 5;
			global.hFont = CreateFontIndirectA(&logfont);
			SelectObject(hdc, global.hFont);

			GetTextMetricsA(hdc, &tm);
			global.cxChar = tm.tmAveCharWidth;
			global.cxCaps = (tm.tmPitchAndFamily & 1 ? 3 : 2) * global.cxChar / 2;
			global.cyChar = tm.tmHeight + tm.tmExternalLeading;

			ReleaseDC(hwnd, hdc);
			return 0;

			case WM_SIZE:
			global.cyClient = HIWORD(lParam);
			global.cxClient = LOWORD(lParam);
			//PRINTF("cxClient = %d, cyClient = %d\n", global.cxClient, global.cyClient);

			global.pixelx = global.cxClient;
			if (global.pixelx < 120)
				global.pixelx = 120;
			if (global.pixelx > (Mcolmx + 1) * 10)
				global.pixelx = (Mcolmx + 1) * 10;
			if (global.pixelx / cast(int) (10 * global.scalex) < 5)
			{
				global.scalex = global.pixelx / (10 * 5.0);
				global.scaley = global.scalex;
			}

			global.pixely = global.cyClient - 40;
			if (global.pixely < 120)
				global.pixely = 120;
			if (global.pixely > (Mrowmx + 1) * 10)
				global.pixely = (Mrowmx + 1) * 10;
			if (global.pixely / cast(int) (10 * global.scaley) < 5)
			{
				global.scaley = global.pixely / (10 * 5.0);
				global.scalex = global.scaley;
			}

			global.text.right = global.pixelx;
			global.sector.right = global.pixelx;
			global.sector.bottom = global.sector.top + global.pixely;

			SetRectRgn(global.sectorRegion, global.sector.left, global.sector.top, global.sector.right, global.sector.bottom);
			SetRectRgn(global.textRegion, global.text.left, global.text.top, global.text.right, global.text.bottom);

			if (global.inited && global.player)
			{

				version(NewDisplay) {
					NewDisplay d = global.player.display;
					d.secbas = -1;
					adjSector(global.scalex, global.scaley);
				} else {
					Display* d = global.player.display;
					d.secbas = -1;
					d.setdispsize(d.text.nrows, d.text.ncols);
					d.text.clear();
					adjSector(global.scalex, global.scaley);
				}
			}

			return 0;

			//case WM_LBUTTONDOWN:
			case WM_RBUTTONDOWN:
			point.x = lParam & 0xFFFF;
			point.y = (lParam >> 16) & 0xFFFF;
			ClientToScreen(hwnd, &point);
			TrackPopupMenu(global.hMenu, 0, point.x, point.y, 0, hwnd, null);
			return 0;

			case WM_COMMAND:
			switch (wParam)
			{
				case IDM_NEW:        // start new game
				if (promptSave(hwnd) &&
				DialogBoxParamA(global.hinst, "InitBox", hwnd,
				&InitDlgProc, 0) == IDOK) {
					//debug MessageBoxA(hwnd, "Entering init_var", "Debug", MB_OK);
					init_var();
					//debug MessageBoxA(hwnd, "Entering winSetup", "Debug", MB_OK);
					winSetup();
					//debug MessageBoxA(hwnd, "Exited winSetup", "Debug", MB_OK);
					global.inited = 1;
					global.dirty = false;
					szFileName[0] = '\0';
					InvalidateRect(hwnd, null, true);
				}
				return 0;

				case IDM_OPEN:        // open saved game
				if (promptSave(hwnd) && GetOpenFileNameA (&global.ofn)) {
					FILE* fp;

					fp = fopen(global.ofn.lpstrFile, "rb");
					if (!fp) {
						MessageBoxA (hwnd, "Empire Restore",
						"Could not read EMP file",
						MB_ICONEXCLAMATION | MB_OK);
					} else {
						init_var();
						if (resgam(fp)) {
							MessageBoxA (hwnd, "Empire Restore",
							"Corrupt EMP file",
							MB_ICONEXCLAMATION | MB_OK);
							winSetup();
						} else {
							winRestore();
						}
						global.inited = 1;
						InvalidateRect(hwnd, null, true);
					}
				}

				return 0;

				case IDM_SAVE:        // save game
				save(hwnd, false);
				return 0;

				case IDM_SAVE_AS:
				save(hwnd, true);
				return 0;

				case IDM_CLOSE:
				if (promptSave(hwnd)) DestroyWindow(hwnd);
				return 0;

				case IDM_SOUND:
				global.speaker ^= 1;
				return 0;

				case IDM_ABOUT:
				DialogBoxParamA(global.hinst, "AboutBox", hwnd,
				&AboutDlgProc, 0);
				return 0;

				case IDM_HELP:
				help(global.hinst);
				return 0;

				case IDM_ZOOMIN:
				goto Lzoomin;

				case IDM_ZOOMOUT:
				goto Lzoomout;

				case IDM_F:      ch = 'F';    goto Linsert;
				case IDM_G:      ch = 'G';    goto Linsert;
				case IDM_H:      ch = 'H';    goto Linsert;
				case IDM_I:      ch = 'I';    goto Linsert;
				case IDM_K:      ch = 'K';    goto Linsert;
				case IDM_L:      ch = 'L';    goto Linsert;
				case IDM_N:      ch = 'N';    goto Linsert;
				case IDM_P:      ch = 'P';    goto Linsert;
				case IDM_R:      ch = 'R';    goto Linsert;
				case IDM_S:      ch = 'S';    goto Linsert;
				case IDM_U:      ch = 'U';    goto Linsert;
				case IDM_Y:      ch = 'Y';    goto Linsert;
				case IDM_ESC:    ch = ESC;    goto Linsert;
				case IDM_FASTER: ch = '<';    goto Linsert;
				case IDM_SLOWER: ch = '>';    goto Linsert;
				case IDM_POV:    ch = 'O';    goto Linsert;

				default:
				break ;
			}
			break ;

			case WM_CHAR:
			switch (wParam)
			{
				version(none)
				{
					case 'c':
					DialogBoxParamA(global.hinst, "CitySelectBox", hwnd,
					global.lpfnCitySelectDlgProc, 0);
					return 0;
				}

				case 'j':
				case 'J':
				global.speaker ^= 1;
				return 0;

				case 12:
				InvalidateRect(hwnd, null, true);
				break ;

				default:
				ch = wParam;
				Linsert:
				// Insert into buffer of player we are watching
				Player* p;

				for (int iPly = 1; iPly <= numply; iPly++)
				{
					p = Player.get(iPly);
					if (p.watch)
					{
						/*	This is a rather primitive solution.  A better
					 *	implementation would check whether the command
					 *	has led to an actual change in the game state.
					 */
						global.dirty = true;
						version(NewDisplay) {
							global.bufferedKey = cast(char) ch;
						} else {
							p.display.text.TTunget(ch);
						}
						break ;
					}
				}
				break ;
			}
			return 0;

			case WM_KEYDOWN:
			switch (wParam)
			{
				case VK_ADD:
				Lzoomin:
				newscalex = global.scalex * 1.125;
				newscaley = global.scaley * 1.125;
				if (global.pixelx / cast(int) (10 * newscalex) >= 5)
				{
					if (newscalex < newscaley)
						newscaley = global.scaley;
					else
						newscaley = newscalex;
					goto Lnew;
				}
				return 0;

				case VK_SUBTRACT:
				Lzoomout:
				newscalex = global.scalex / 1.125;
				newscaley = global.scaley / 1.125;
				if (global.pixelx / cast(int) (10 * newscalex) <= (Mcolmx + 1))
				{
					if (global.pixely / cast(int) (10 * newscaley) > (Mrowmx + 1))
						newscaley = global.scaley;
					//PRINTF("newscale x,y = %g, %g\n", newscalex, newscaley);
					Lnew:

					adjSector(newscalex, newscaley);

					InvalidateRect(hwnd, &global.sector, false);
				}
				return 0;

				case VK_PRIOR:    // PgUp
				case VK_NEXT:    // PgDn
				case VK_HOME:
				case VK_LEFT:
				case VK_RIGHT:
				case VK_UP:
				case VK_DOWN:
				return 0;

				default:
				break ;
			}
			break ;

			case WM_PAINT:
			//PRINTF("+WM_PAINT\n");
			hdc = BeginPaint (hwnd, &ps);

			if (!global.inited || !global.player)
			{
				double sx, sy;

				version (0)
				{
					sx = global.cxClient / 240.0;
					if (sx < 1)
						sx = 1;
					sy = global.cyClient / 120.0;
					if (sy < 1)
						sy = 1;
				}
				else
				{
					sx = global.cxClient / 120.0;
					if (sx < 1)
						sx = 1;
					sy = global.cyClient / 160.0;
					if (sy < 1)
						sy = 1;
				}
				DrawBitmap(hdc, 0, 0, global.hSplash,
				sx, sy,
				SRCCOPY);
				static int intro;
				if (!intro++)
					PlaySoundA("intro.wav", null, SND_ASYNC | SND_FILENAME);
			}
			else
			{

				//PRINTF("WM_PAINT: ulcorner = %d, cursor = %d, offsetx = %d, offsety = %d\n", global.ulcorner, global.cursor, global.offsetx, global.offsety);
				int r, c;
				int dx;
				int dy;
				DWORD mode;
				RECT clipbox;

				GetClipBox(hdc, &clipbox);
				//PRINTF("sector : %2d,%2d %2d,%2d\n", global.sector.left, global.sector.top, global.sector.right, global.sector.bottom);
				//PRINTF("clipbox: %2d,%2d %2d,%2d\n", clipbox.left, clipbox.top, clipbox.right, clipbox.bottom);
				if (clipbox.bottom < global.sector.top)
					goto LpaintText;

				SelectClipRgn(hdc, global.sectorRegion);

				r = ROW(global.ulcorner);
				c = COL(global.ulcorner);
				{
				int rmax, cmax;
				dx = cast(int)(10 * global.scalex);
				dy = cast(int)(10 * global.scaley);
				rmax = r + (global.offsety + global.pixely + dy - 1) / dy;
				cmax = c + (global.offsetx + global.pixelx + dx - 1) / dx;
				if (rmax > Mrowmx)
					rmax = Mrowmx + 1;
				if (cmax > Mcolmx)
					cmax = Mcolmx + 1;
				debug (hilite) {
					static loc_t lastCursor;
					if (global.cursor != lastCursor) {
						MessageBoxA(hwnd, format("Cursor %d, %d",
						ROW(global.cursor), COL(global.cursor)), "Debug",
						MB_OK);
						lastCursor = global.cursor;
					}
				}
				for (j = r; j < rmax; j++)
				{
					int y;

					y = global.sector.top + (j - r) * dy - global.offsety;
					if (y >= clipbox.bottom ||
					y + dy < clipbox.top)
						continue ;

					for (i = c; i < cmax; i++)
					{
						loc_t loc = j * (Mcolmx + 1) + i;
						HANDLE h;
						int x;

						x =  (i - c) * dx - global.offsetx;
						if (x >= clipbox.right ||
						x + dx < clipbox.left)
							continue ;

						h = global.mapvaltab[global.map[loc]];
						if ((j % 10) == 0 && (i % 10) == 0 &&
						global.map[loc] == 0)
							h = global.unknown10;
						mode = SRCCOPY;

						if (/+global.player.num == plynum
						  &&+/ loc == global.cursor
						&& global.cursor > LOC_LASTMAGIC
						//&& !global.player.display.cursorHidden
						&& global.player.mode != mdSURV) {
							/+debug (hilite) MessageBoxA(hwnd,
						  format("Cursor %d, %d", r, c), "Debug", MB_OK);+/
							mode = NOTSRCCOPY;
						}

						DrawBitmap(hdc, cast(short)x, cast(short)y, h,
						global.scalex, global.scaley, mode);
					}
				}
			}
				// Draw a rectangle around the map edge
				{
				int x1,y1,x2,y2;
				x1 = -c * dx - global.offsetx;
				y1 = 40 - r * dx - global.offsety;
				x2 = x1 + (Mcolmx + 1) * dx - 1;
				y2 = y1 + (Mrowmx + 1) * dy - 1;
				{
					HPEN borderPen = CreatePen(PS_SOLID, dx/3+2, RGB(255, 0, 0));
					SelectObject(hdc, borderPen);

					MoveToEx(hdc, x1, y1, null);
					LineTo(hdc, x2, y1);
					LineTo(hdc, x2, y2);
					LineTo(hdc, x1, y2);
					LineTo(hdc, x1, y1);

					SelectObject(hdc, global.dashedPen);
					DeleteObject(borderPen);
				}
				}

				// Do the blast graphic
				if (global.blastState)
				{
					DrawBitmap(hdc, cast(short)global.blastx, cast(short)global.blasty, global.hBlastmask, 1.0, 1.0, SRCAND);
					DrawBitmap(hdc, cast(short)global.blastx, cast(short)global.blasty, global.hBlast, 1.0, 1.0, SRCPAINT);
				}

				// Do the survey mode graphic
				if (global.player && global.player.mode == mdSURV)
				{
					HPEN hPen;
					int x1s, y1s, x2s, y2s;
					int cursorx, cursory;

					cursorx = LocToX(global.player.curloc);
					cursory = LocToY(global.player.curloc);

					x1s = 0;
					y1s = cursory;
					x2s = cursorx - dx/2;
					y2s = y1s;
					MoveToEx(hdc, x1s, y1s, null);
					LineTo(hdc, x2s, y2s);

					x1s = x2s + dx;
					x2s = global.pixelx;
					MoveToEx(hdc, x1s, y1s, null);
					LineTo(hdc, x2s, y2s);

					x1s = cursorx;
					y1s = 40;
					x2s = x1s;
					y2s = cursory - dy/2;
					MoveToEx(hdc, x1s, y1s, null);
					LineTo(hdc, x2s, y2s);

					y1s = y2s + dy;
					y2s = 40 + global.pixely;
					MoveToEx(hdc, x1s, y1s, null);
					LineTo(hdc, x2s, y2s);
				}

				// Do the direction mode graphic
				if (global.player && global.player.mode == mdDIR)
				{
					HPEN hPen;
					int x1s, y1s, x2s, y2s;
					int cursorx, cursory;

					cursorx = LocToX(global.player.curloc);
					cursory = LocToY(global.player.curloc);

					/* -O */
					x1s = cursorx - dx/2 - 2 * dx;
					x2s = cursorx - dx/2;
					y1s = y2s = cursory;
					MoveToEx(hdc, x1s, y1s, null);
					LineTo(hdc, x2s, y2s);

					/* \
				 *  O
				 */
					y1s -= 2 * dy + dy/2;
					y2s -= dy/2;
					MoveToEx(hdc, x1s, y1s, null);
					LineTo(hdc, x2s, y2s);

					/*  O
				 * /
				 */
					y1s += dy * 5;
					y2s += dy;
					MoveToEx(hdc, x1s, y1s, null);
					LineTo(hdc, x2s, y2s);

					/*  O
				 *  |
				 */
					x1s = x2s = cursorx;
					MoveToEx(hdc, x1s, y1s, null);
					LineTo(hdc, x2s, y2s);

					/*  O
				 *   \
				 */
					x1s += (dx - dx/2) + 2 * dx;
					x2s += (dx - dx/2);
					MoveToEx(hdc, x1s, y1s, null);
					LineTo(hdc, x2s, y2s);

					/*  O- */
					y1s = y2s = cursory;
					MoveToEx(hdc, x1s, y1s, null);
					LineTo(hdc, x2s, y2s);

					/*   /
				 *  O
				 */
					y1s -= dy/2 + 2 * dy;
					y2s -= dy/2;
					MoveToEx(hdc, x1s, y1s, null);
					LineTo(hdc, x2s, y2s);

					/*  |
				 *  O
				 */
					x1s = x2s = cursorx;
					MoveToEx(hdc, x1s, y1s, null);
					LineTo(hdc, x2s, y2s);
				}

				// Do the move mode graphic
				if (global.player && global.player.mode == mdTO)
				{
					HPEN hPen;
					int x1s, y1s, x2s, y2s;

					x1s = LocToX(global.player.frmloc);
					y1s = LocToY(global.player.frmloc);
					x2s = LocToX(global.player.curloc);
					y2s = LocToY(global.player.curloc);
					MoveToEx(hdc, x1s, y1s, null);
					if (x1s != x2s && y1s != y2s)
					{
						int x, y;
						int ax, ay;

						ax = maps.abs(x1s - x2s);
						ay = maps.abs(y1s - y2s);
						if (ax < ay)
						{
							x = x2s;
							if (y1s < y2s)
								y = y1s + ax;
							else
								y = y1s - ax;
						}
						else
						{
							if (x1s < x2s)
								x = x1s + ay;
							else
								x = x1s - ay;
							y = y2s;
						}
						LineTo(hdc, x, y);
					}
					LineTo(hdc, x2s, y2s);
				}

				LpaintText:
				if (clipbox.bottom > global.text.top &&
				clipbox.top < global.text.bottom)
				{
					// Do the text box
					SelectClipRgn(hdc, global.textRegion);

					// Fill background
					FillRect(hdc, &global.text, GetStockObject(WHITE_BRUSH));

					SelectObject(hdc, global.hFont);


					version(NewDisplay) {
						int col2 = global.text.right * 2 / 3;
						int col3 = global.text.right * 5 / 6;
						StatusPanel sp = global.player.display.panel;
					}
					for (i = 0; i < 4; i++)
					{
						version(NewDisplay){
							TextOutA(hdc, 0, global.cyChar * i, sp[i].ptr, sp[i].length);
							TextOutA(hdc, col2, global.cyChar * i,
							sp[i | 4].ptr, sp[i | 4].length);
							TextOutA(hdc, col3, global.cyChar * i,
							sp[i | 8].ptr, sp[i | 8].length);
						} else {
							TextOutA(hdc, 0, global.cyChar * i, vbuffer[i].ptr, strlen(vbuffer[i].ptr));
						}
					}
				}
			}

			EndPaint (hwnd, &ps);
			//PRINTF("-WM_PAINT\n");
			return 0;

			case WM_CLOSE:
			if (promptSave(hwnd)) DestroyWindow(hwnd);
			return 0;

			case WM_QUERYENDSESSION:
			return promptSave(hwnd);

			case WM_DESTROY:

			for (i = 0; i < MAPMAX; i++)
			{
				if (global.mapvaltab[i])
					DeleteObject(global.mapvaltab[i]);
			}

			DeleteObject(global.unknown10);
			DeleteObject(global.hBlast);
			DeleteObject(global.hBlastmask);
			DeleteObject(global.hSplash);
			DeleteObject(global.hCursor);
			DeleteObject(global.hFont);
			DeleteObject(global.sectorRegion);
			DeleteObject(global.textRegion);

			hdc = GetDC(hwnd);
			SelectObject(hdc, global.originalPen);
			ReleaseDC(hwnd, hdc);
			DeleteObject(global.dashedPen);

			PostQuitMessage (0);
			return 0;

			default:
			break ;
		}
	}
	catch (Exception ignored) {
		try {
			MessageBoxA(null, cast(char*) ignored.toString(), "Error",
			MB_OK | MB_ICONEXCLAMATION);
		} catch (Exception fullyIgnored) {

		}
	}
	return DefWindowProcA(hwnd, message, wParam, lParam);
}


/**
 *	Saves the current game.
 *
 *	Returns:
 *		true	success
 *		false	error
 */
bool save(HWND hwnd, bool saveAs) {
	int named = true;

	if (saveAs || global.sfn.lpstrFile[0] == '\0') {
		named = GetSaveFileNameA(&global.sfn);
	}

	if (named) {
		if (var_savgam(global.sfn.lpstrFile)) {
			MessageBoxA(hwnd, "Empire Save",
			  "Could not write EMP file",
			  MB_ICONEXCLAMATION | MB_OK);
			return false;
		}
		global.dirty = false;
		return true;
	} else {
		return false;
	}
}

/**
 *	Prompts to save the current game if necessary.
 *
 *	Returns:
 *		true	successfully saved, no need to save, or No was chosen
 *		false	failed or cancelled
 */
bool promptSave(HWND hwnd) {
	if (!global.dirty) return true;

	string message = (global.sfn.lpstrFile[0] == '\0') ?
	  "Save game?" :
	  "Save changes to " ~ to!string(global.sfn.lpstrFile) ~ "?\0";

	final switch (MessageBoxA(hwnd, message.ptr,
		  "Game has changed", MB_ICONQUESTION | MB_YESNOCANCEL)) {
		case IDYES:
			return save(hwnd, false);

		case IDNO:
			return true;

		case IDCANCEL:
			return false;
	}
}


/********************************************
 * "About" dialog box.
 */

extern (Windows) BOOL AboutDlgProc (HWND hDlg, uint message, uint wParam,
					                                           LONG lParam) nothrow
{
	switch (message)
	{
		case WM_INITDIALOG:
			return true;

		case WM_COMMAND:
			final switch (wParam)
			{
				case IDOK:
				case IDCANCEL:
					EndDialog (hDlg, 0);
					return true;
			}
			break;

		default:
			break;
	}
	return false;
}

/********************************************
 * "City Select" dialog box.
 */

extern (Windows) BOOL CitySelectDlgProc(HWND hDlg, uint message, uint wParam,
					                                           LONG lParam) nothrow
{
	static HWND hSensor;
	static HWND hTile;
	BOOL result = false;

	HDC hDC;
	RECT rect;
	int r, c;
	int dx, dy;
	double scalex, scaley;
	int i, j;

	try {
		switch (message)
		{
			case WM_INITDIALOG:

			global.newphase = global.phase;
			CheckRadioButton(hDlg, IDD_ARMIES, IDD_BATTLESHIPS, global.newphase);

			hSensor = GetDlgItem(hDlg, IDD_SENSOR);
			hTile = GetDlgItem(hDlg, IDD_TILE);

			SetFocus(GetDlgItem(hDlg, global.newphase));
			return true;

			case WM_COMMAND:
			switch (wParam)
			{
				case IDOK:
				global.phase = global.newphase;
				EndDialog (hDlg, true);
				return true;

				case IDCANCEL:
				EndDialog (hDlg, false);
				return true;

				case IDD_ARMIES:
				case IDD_FIGHTERS:
				case IDD_DESTROYERS:
				case IDD_TRANSPORTS:
				case IDD_SUBMARINES:
				case IDD_CRUISERS:
				case IDD_CARRIERS:
				case IDD_BATTLESHIPS:
				global.newphase = wParam;
				CheckRadioButton(hDlg, IDD_ARMIES, IDD_BATTLESHIPS, global.newphase);
				result = true;
				goto LpaintTile;

				default:
				break ;
			}
			break ;

			case WM_PAINT:

			// Sensor probe
			InvalidateRect(hSensor, null, true);
			UpdateWindow(hSensor);

			hDC = GetDC(hSensor);
			GetClientRect(hSensor, &rect);

			r = ROW(global.cursor) - 2;
			if (r < 0)
				r = 0;
			if (r + 5 > Mrowmx)
				r = Mrowmx - 5;
			c = COL(global.cursor) - 2;
			if (c < 0)
				c = 0;
			if (c + 5 > Mcolmx)
				c = Mcolmx - 5;

			dx = (rect.right - rect.left) / 5;
			dy = (rect.bottom - rect.top) / 5;
			scalex = dx / cast(double) 10;
			scaley = dy / cast(double) 10;

			for (j = 0; j < 5; j++)
			{
				for (i = 0; i < 5; i++)
				{
					loc_t loc = (r + j) * (Mcolmx + 1) + (c + i);
					HANDLE h = global.mapvaltab[global.map[loc]];

					DrawBitmap(hDC, cast(short)(rect.left + i * dx), cast(short)(rect.top + j * dy),
					h, scalex, scaley, SRCCOPY);
				}
			}

			ReleaseDC(hSensor, hDC);

			LpaintTile:
			// Sample Tile

			InvalidateRect(hTile, null, true);
			UpdateWindow(hTile);

			hDC = GetDC(hTile);
			GetClientRect(hTile, &rect);

			dx = rect.right - rect.left;
			dy = rect.bottom - rect.top;
			scalex = dx / cast(double) 10;
			scaley = dy / cast(double) 10;

			{
				int ab = global.newphase - IDD_ARMIES;
				HANDLE h = global.mapvaltab[ab + ((ab <= F) ? 5 : 6)];

				DrawBitmap(hDC, cast(short)rect.left, cast(short)rect.top,
				h, scalex, scaley, SRCCOPY);
			}

			ReleaseDC(hTile, hDC);
			break ;

			default:
			break ;
		}
	}  catch (Exception ignored) {
		try {
			MessageBoxA(null, cast(char*) ignored.toString(), "Error",
			MB_OK | MB_ICONEXCLAMATION);
		} catch (Exception fullyIgnored) {

		}
	}
	return result;
}


/********************************
 * Dialog box to get city phase.
 * Returns:
 *	new phase
 */

int dialogCitySelect(int oldphase)
{
	//PRINTF("dialogCitySelect(oldphase = %d)\n", oldphase);
	UpdateWindow(global.hwnd);
	if (oldphase & ~7)
		oldphase = 0;		// default to armies
	global.phase = oldphase + IDD_ARMIES;

	DialogBoxParamA(global.hinst, "CitySelectBox", global.hwnd,
	  &CitySelectDlgProc, 0);

	//PRINTF("dialogCitySelect() = %d\n", global.phase - IDD_ARMIES);
	return global.phase - IDD_ARMIES;
}


/********************************************
 * "Init" dialog box.
 */

extern (Windows) BOOL InitDlgProc (HWND hDlg, uint message, uint wParam,
					                                           LONG lParam) nothrow
{
	switch (message)
	{
		case WM_INITDIALOG:

		global.newnumplayers = global.numplayers;
		CheckRadioButton(hDlg, IDD_ONE, IDD_SIX, global.newnumplayers);
		if (global.demo)
		CheckRadioButton(hDlg, IDD_DEMO, IDD_DEMO, IDD_DEMO);
		SetFocus(GetDlgItem(hDlg, global.newnumplayers));
			return true;

		case WM_COMMAND:
			switch (wParam)
			{
				case IDOK:
					global.numplayers = global.newnumplayers;
							EndDialog (hDlg, true);
					return true;

				case IDCANCEL:
							EndDialog (hDlg, false);
					return true;

				case IDD_ONE:
				case IDD_TWO:
				case IDD_THREE:
				case IDD_FOUR:
				case IDD_FIVE:
				case IDD_SIX:
					global.newnumplayers = wParam;
					CheckRadioButton(hDlg, IDD_ONE, IDD_SIX, global.newnumplayers);
					return true;

				case IDD_DEMO:
					global.demo ^= 1;
					CheckRadioButton(hDlg, IDD_DEMO, IDD_DEMO, global.demo ? IDD_DEMO : IDD_DEMO + 1);
					return true;

				default:
					break;
			}
			break;

	default:
		break;
	}
	return false;
}




/******************************
 * Flush the display.
 */

extern (C) void win_flush()
{
	InvalidateRect(global.hwnd, &global.text, false);
	UpdateWindow(global.hwnd);
}

/******************************
 * Click the speaker.
 */

extern (C) void sound_click()
{
	UpdateWindow(global.hwnd);
	if (global.speaker)
		PlaySoundA("click.wav", null, SND_ASYNC | SND_FILENAME | SND_NOSTOP);
}

void sound_gun()
{
	UpdateWindow(global.hwnd);
	if (global.speaker)
		PlaySoundA("gun_1.wav", null, SND_SYNC | SND_FILENAME);
}

void sound_bang()
{
	UpdateWindow(global.hwnd);
	if (global.speaker)
	{
		PlaySoundA("explosi1.wav", null, SND_SYNC | SND_FILENAME);
		PlaySoundA("bubbles.wav", null, SND_SYNC | SND_FILENAME);
	}
}

void sound_error()
{
	UpdateWindow(global.hwnd);
	if (global.speaker)
		PlaySoundA("error.wav", null, SND_SYNC | SND_FILENAME);
}

void sound_splash()
{
	UpdateWindow(global.hwnd);
	if (global.speaker)
		PlaySoundA("splash.wav", null, SND_SYNC | SND_FILENAME);
}

void sound_aground()
{
	UpdateWindow(global.hwnd);
	if (global.speaker)
		PlaySoundA("bubbles.wav", null, SND_SYNC | SND_FILENAME);
}

void sound_subjugate()
{
	UpdateWindow(global.hwnd);
	if (global.speaker)
		PlaySoundA("machine1.wav", null, SND_SYNC | SND_FILENAME);
}

void sound_crushed()
{
	UpdateWindow(global.hwnd);
	if (global.speaker)
		PlaySoundA("gun_3.wav", null, SND_SYNC | SND_FILENAME);
}

void sound_flyby()
{
	UpdateWindow(global.hwnd);
	if (global.speaker)
		PlaySoundA("flyby.wav", null, SND_SYNC | SND_FILENAME);
}

void sound_fcrash()
{
	UpdateWindow(global.hwnd);
	if (global.speaker)
		PlaySoundA("explode.wav", null, SND_SYNC | SND_FILENAME);
}

void sound_fuel()
{
	UpdateWindow(global.hwnd);
	if (global.speaker)
		PlaySoundA("fuel.wav", null, SND_SYNC | SND_FILENAME);
}

void sound_taps()
{
	UpdateWindow(global.hwnd);
	if (global.speaker)
		PlaySoundA("taps.wav", null, SND_SYNC | SND_FILENAME);
}

void sound_ackack()
{
	UpdateWindow(global.hwnd);
	if (global.speaker)
		PlaySoundA("ackack1.wav", null, SND_SYNC | SND_FILENAME);
}

/***********************************
 * Setup for Windows.
 * Equivalent to main.setup().
 */

void winSetup()
{
	//PRINTF("winSetup()\n");
	debug
	{
		// set random number generator to predictable value
		setran();
	}

	//Text* t = &player[0].display.text;

	//printf("Please wait seven days for creation of world...\n");
	selmap();			// read in map
	citini();			// init city variables

	numply = global.numplayers - IDD_ONE + 1;
	numleft = numply;
	for (plynum = 0; plynum <= numply; plynum++)
	{
		//PRINTF("player %d\n", plynum);
		Player* p = &player[plynum];

		version(NewDisplay) {
			NewDisplay d = p.display = new NewDisplay();
		} else {
			Display* d = p.display = new Display();
			d.initialize();
		}
		p.num = plynum;
		p.map = ((plynum == 0) ? .map : new ubyte[MAPSIZE]).ptr;
		p.human = (plynum == 1 && !global.demo);
		p.watch = DAnone;

		if (p.human)
		{
			d.timeinterval = 1;
		}

		if (plynum == 1)
		{
			p.secflg = 1;
			p.watch = DAwindows;
			version(NewDisplay) {
				d.panel.isActive = true;
			} else {
				d.text.TTinit();
				d.text.watch = p.watch;
				d.maptab = MTcgacolor;
				d.setdispsize(d.text.nrows, d.text.ncols);
				d.text.clear();
				d.text.block_cursor();
			}
		}
		if (plynum)
			p.citsel();		// select city for each player
	}

	plynum = 1;			// get the default player
	global.player = &player[1];
}

void winRestore()
{
	//PRINTF("winRestore()\n");
	debug
	{
		setran();		// seed random number generator
	}

	/+Text* t = &player[0].display.text;

	t.TTinit();+/

	for (plynum = 0; plynum <= numply; plynum++)
	{
		Player* p = &player[plynum];
		version(NewDisplay) {
			NewDisplay d = p.display = new NewDisplay();
		} else {
			Display* d = p.display = new Display();
			d.initialize();
		}


		if (p.human)
		{
			d.timeinterval = 1;
		}

		if (plynum == 1)
		{
			p.secflg = 1;
			p.watch = DAwindows;

			version(NewDisplay){
				d.panel.isActive = true;
			} else {
				d.text.TTinit();
				d.text.watch = p.watch;
				d.maptab = MTcgacolor;
				d.setdispsize(d.text.nrows, d.text.ncols);
				d.text.clear();
				d.text.block_cursor();
			}
		}
	}
	plynum = 1;			// get the default player
}

/***************************************
 * Given new scale factors x,y, adjust sector location.
 * Returns:
 *	!=0 if sector moved
 */

bool adjSector(double newscalex, double newscaley)
{
	int cursorx;
	int dx;
	int ncols;
	int scmin;
	int scmax;

	int cursory;
	int dy;
	int nrows;
	int srmin;
	int srmax;

	int gap;
	int n;
	int width;
	version(NewDisplay) {
		NewDisplay d;
	} else {
		Display* d;
	}

	bool moved = false;
	int newval;

	// todo Stewart removed this, added as a last resort.
	if (!global.player)	 return false;	// if not initialized yet
	if (global.cursor <= LOC_LASTMAGIC) return false;

//PRINTF("Before: ulcorner = %d\n", global.ulcorner);
	ncols = COL(global.cursor) - COL(global.ulcorner);
//PRINTF("cursor = %d, diff = %d, ncols = %d\n", global.cursor, global.cursor - global.ulcorner, ncols);
	dx = cast(int)(10 * global.scalex);
	cursorx = ncols * dx + (dx / 2) - global.offsetx;
	dx = cast(int)(10 * newscalex);
	n = (cursorx - (dx / 2) + (dx - 1)) / dx;
//PRINTF("n = %d, cursorx = %d, dx = %d\n", n, cursorx, dx);
	if (cursorx < dx + (dx / 2))
	{
		n = 1;
		cursorx = n * dx + (dx / 2);
	}
	if (COL(global.cursor) < n)
	{
		n = COL(global.cursor);
		cursorx = n * dx + (dx / 2);
	}
	width = (global.pixelx + (dx - 1)) / dx;
//PRINTF("n = %d, width = %d\n", n, width);

	// Right justify right edge
	gap = cursorx - dx/2 + 3 * dx - global.pixelx;
	if (gap > 0)
	{
		cursorx -= gap;
		n = (cursorx - (dx / 2) + (dx - 1)) / dx;
		//PRINTF("1adj gap = %d\n", gap);
	}
	gap = global.pixelx - (((Mcolmx + 1) - COL(global.cursor)) * dx + cursorx - dx/2);
	if (gap > 0)
	{
		cursorx += gap;
		n = (cursorx - (dx / 2) + (dx - 1)) / dx;
		//PRINTF("2adj gap = %d\n", gap);
		if (COL(global.cursor) < n)
		{
			n = COL(global.cursor);
			cursorx = n * dx + (dx / 2);
		}
	}

	newval = dx * n + dx / 2 - cursorx;
	if (newval != global.offsetx)
		moved = true;
	global.offsetx = newval;
//PRINTF("offsetx = %d\n", global.offsetx);
	scmin = COL(global.cursor) - n;
	scmax = (width - 1);
//PRINTF("n = %d, width = %d, scmin = %d, COL(cursor) = %d\n", n, width, scmin, COL(global.cursor));
	assert(scmin <= COL(global.cursor));

	nrows = ROW(global.cursor) - ROW(global.ulcorner);
//PRINTF("cursor = %d, diff = %d, nrows = %d\n", global.cursor, global.cursor - global.ulcorner, nrows);
	dy = cast(int)(10 * global.scaley);
	cursory = nrows * dy + (dy / 2) - global.offsety;
	dy = cast(int)(10 * newscaley);
	n = (cursory - (dy / 2) + (dy - 1)) / dy;
//PRINTF("n = %d, cursory = %d, dy = %d\n", n, cursory, dy);
	if (cursory < dy + (dy / 2))
	{
		n = 1;
		cursory = n * dy + (dy / 2);
	}
	if (ROW(global.cursor) < n)
	{
		n = ROW(global.cursor);
		cursory = n * dy + dy / 2;
		//PRINTF("adjust top\n");
	}
	width = (global.pixely + (dy - 1)) / dy;

	// Bottom justify bottom edge
	gap = cursory - dy/2 + 3 * dy - global.pixely;
	if (gap > 0)
	{
		cursory -= gap;
		n = (cursory - (dy / 2) + (dy - 1)) / dy;
	}
	gap = global.pixely - (((Mrowmx + 1) - ROW(global.cursor)) * dy + cursory - dy/2);
	if (gap > 0)
	{
		cursory += gap;
		n = (cursory - (dy / 2) + (dy - 1)) / dy;
		if (ROW(global.cursor) < n)
		{
			n = ROW(global.cursor);
			cursory = n * dy + dy / 2;
		}
	}

	newval = dy * n + dy / 2 - cursory;
	if (newval != global.offsety)
		moved = true;
	global.offsety = newval;
	srmin = ROW(global.cursor) - n;
	srmax = (width - 1);
//PRINTF("n = %d, height = %d, srmin = %d\n", n, width, srmin);

	d = global.player.display;
	//d.Smin = srmin * 256 + scmin;
	d.Smax = srmax * 256 + scmax;

	newval = srmin * (Mcolmx + 1) + scmin;
	if (newval != global.ulcorner)
		moved = true;
	global.ulcorner = newval;
	d.secbas = global.ulcorner;
//PRINTF("offsetx = %d, offsety = %d\n", global.offsetx, global.offsety);
//PRINTF("After: ulcorner = %d, Smin = %x, Smax = %x\n", global.ulcorner, d.Smin, d.Smax);

	assert(global.ulcorner >= 0 && global.ulcorner < MAPSIZE);
	assert(global.ulcorner <= global.cursor && global.cursor < MAPSIZE);
	assert(COL(global.ulcorner) <= COL(global.cursor));
	assert(dx > 0 && dy > 0);
	assert(global.offsetx >= 0 && global.offsetx < dx);
	assert(global.offsety >= 0 && global.offsety < dy);

	global.scalex = newscalex;
	global.scaley = newscaley;

	return moved;
}

/*************************************
 * Invalidate display of loc on the screen, so
 * it will get updated.
 */

void invalidateLoc(loc_t loc)
in {
	assert (loc < MAPSIZE);
}
do {
	RECT rect;
	int r, c;
	int dx;
	int dy;
	DWORD mode;

//PRINTF("invalidateLoc(loc = %d)\n", loc);

	if (loc <= LOC_LASTMAGIC) return;  // no current cursor

	r = ROW(loc) - ROW(global.ulcorner);
	c = COL(loc) - COL(global.ulcorner);
	dx = cast(int)(10 * global.scalex);
	dy = cast(int)(10 * global.scaley);

	rect.left = c * dx - global.offsetx;
	rect.top = 40 + r * dy - global.offsety;
	rect.right = rect.left + dx;
	rect.bottom = rect.top + dy;

	InvalidateRect(global.hwnd, &rect, false);
}

/*************************************
 * Invalidate display of rectangle formed by corners loc1, loc2
 * on the screen, so
 * it will get updated.
 */

void invalidateLocRect(loc_t loc1, loc_t loc2)
{
	RECT rect;
	int r1, c1;
	int r2, c2;
	int dx;
	int dy;
	DWORD mode;

//PRINTF("invalidateLoc(loc = %d)\n", loc);
	assert(loc1 < MAPSIZE);
	assert(loc2 < MAPSIZE);

	r1 = ROW(loc1) - ROW(global.ulcorner);
	c1 = COL(loc1) - COL(global.ulcorner);
	r2 = ROW(loc2) - ROW(global.ulcorner);
	c2 = COL(loc2) - COL(global.ulcorner);

	if (r1 > r2)
	{	int r;
	r = r1;
	r1 = r2;
	r2 = r;
	}
	if (c1 > c2)
	{	int c;
	c = c1;
	c1 = c2;
	c2 = c;
	}

	dx = cast(int)(10 * global.scalex);
	dy = cast(int)(10 * global.scaley);

	rect.left = c1 * dx - global.offsetx;
	rect.top = 40 + r1 * dy - global.offsety;
	rect.right = rect.left + dx * (c2 - c1 + 1);
	rect.bottom = rect.top + dy * (r2 - r1 + 1);

	InvalidateRect(global.hwnd, &rect, false);
}

/******************************************
 * Invalidate entire sector.
 */

void invalidateSector()
{
	InvalidateRect(global.hwnd, &global.sector, false);
}

/******************************************
 * Convert loc to screen coordinate.
 */

int LocToX(loc_t loc)
{
	int dx;
	int x;
	int col;

	col = COL(loc) - COL(global.ulcorner);
	dx = cast(int)(10 * global.scalex);
	x = col * dx + dx / 2 - global.offsetx;
	return x;
}

int LocToY(loc_t loc)
{
	int dy;
	int y;
	int row;

	row = ROW(loc) - ROW(global.ulcorner);
	dy = cast(int)(10 * global.scaley);
	y = 40 + row * dy + dy / 2 - global.offsety;
	return y;
}

/*********************************************
 * Start/Stop blast graphic.
 */

void ShowBlast(int state, loc_t loc)
{
	RECT blastbox;
	int x, y;

	x = LocToX(loc);
	y = LocToY(loc);
	blastbox.bottom = y + 5;
	blastbox.top = blastbox.bottom - 20;
	blastbox.left = x - 10;
	blastbox.right = x + 10;
	InvalidateRect(global.hwnd, &blastbox, false);
	global.blastState = state;
	global.blastx = blastbox.left;
	global.blasty = blastbox.top;
	if (state)
		UpdateWindow(global.hwnd);
}
version(NewDisplay)
{
	/**
 * Retrieve a buffered keystroke and clear it
 */
	char getKeystroke() {
	char key = peekKeystroke();
		global.bufferedKey = char.init;
		return key;
	}

	/**
 * Retrieve a buffered keystroke without clearing it
 */
	char peekKeystroke() {
	// toUpper() turns char.init (==255) 376 and then cast(char) turns it into 120 == ('x')
	return global.bufferedKey == char.init ? char.init : cast(char) toUpper(global.bufferedKey);
	}
}
