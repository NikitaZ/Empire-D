/*
 * Empire, the Wargame of the Century (tm)
 * Copyright (C) 1978-2004 by Walter Bright
 * All Rights Reserved
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

/*-----------------------------------------------------
   Adapted from:
   SYSMETS.C -- System Metrics Display Program (Final)
	            (c) Charles Petzold, 1992
  -----------------------------------------------------*/

import core.sys.windows.windows;
import core.stdc.stdio;
import core.stdc.stdlib;
import std.file;
import std.path;
import std.string;

extern (Windows) BOOL DestroyWindow(HWND hWnd);

int min(int a, int b) { return (a < b) ? a : b; }
int max(int a, int b) { return (a > b) ? a : b; }

int inhelp;
string szAppName = "TextWin";
char[] helpFilePath;


void helpRegister(HANDLE hInstance)
{
	WNDCLASSA    wndclass;

	wndclass.style         = CS_HREDRAW | CS_VREDRAW;
	wndclass.lpfnWndProc   = &TextWndProc;
	wndclass.cbClsExtra    = 0;
	wndclass.cbWndExtra    = 0;
	wndclass.hInstance     = hInstance;
	wndclass.hIcon         = LoadIcon(hInstance, IDI_APPLICATION);
	wndclass.hCursor       = LoadCursor(hInstance, IDC_ARROW);
	wndclass.hbrBackground = GetStockObject(WHITE_BRUSH);
	wndclass.lpszMenuName  = null;
	wndclass.lpszClassName = szAppName.ptr;

	RegisterClassA(&wndclass);

	// generate help file path
	char[MAX_PATH] filePath;
	int len = GetModuleFileNameA(hInstance, filePath.ptr, filePath.length);
	helpFilePath = join([dirName(filePath[0..len]), `\help.txt`], dirSeparator).dup;
}

void help(HANDLE hInstance)
{
	HWND        hwnd;
	MSG         msg;
	WNDCLASS    wndclass;

	if (inhelp)
		return;
	inhelp++;
	hwnd = CreateWindowA (szAppName.ptr, "Empire Help",
					  WS_OVERLAPPEDWINDOW | WS_VSCROLL | WS_HSCROLL,
					  CW_USEDEFAULT, CW_USEDEFAULT,
					  CW_USEDEFAULT, CW_USEDEFAULT,
					  null, null, hInstance, null);

	ShowWindow(hwnd, SW_SHOWNORMAL);
	UpdateWindow(hwnd);
}

extern(Windows) LRESULT TextWndProc (HWND hwnd, UINT message, WPARAM wParam,
	                                                      LPARAM lParam) nothrow @system
{
	static int  cxChar, cxCaps, cyChar, cxClient, cyClient, nMaxWidth,
	               nVscrollPos, nVscrollMax, nHscrollPos, nHscrollMax;
    char[10]          szBuffer ;
	HDC           hdc;
	int         x, y, nPaintBeg, nPaintEnd, nVscrollInc, nHscrollInc;
	PAINTSTRUCT   ps;
	TEXTMETRICA   tm;

	static char[] buffer;
	static int numlines;

	char *p;
	int i;

	try {
		switch (message)
		{
			case WM_CREATE:

			debug (twin) {
				MessageBoxA(hwnd, toStringz(helpFilePath), "Debug",
				MB_OK);
			}

			try {
				buffer = cast(char[]) std.file.read(helpFilePath);

			} catch (FileException ex) {
				MessageBoxA(hwnd, toStringz(ex.toString),
				"Cannot display help", MB_OK | MB_ICONEXCLAMATION);
				DestroyWindow(hwnd);
			}

			numlines = 0;
			nMaxWidth = 0;
			p = buffer.ptr;
			for (i = 0; i < buffer.length; i++)
			{
				if (buffer[i] == '\n')
				{
					int width = &buffer[i] - p;

					if (i && buffer[i - 1] == '\r')
						width--;
					if (width > nMaxWidth)
						nMaxWidth = width;
					numlines++;
					if (i + 1 < buffer.length)
						p = &buffer[i + 1];
				}
			}

			hdc = GetDC (hwnd);

			SelectObject(hdc, GetStockObject(SYSTEM_FIXED_FONT));
			GetTextMetricsA(hdc, &tm);
			cxChar = tm.tmAveCharWidth;
			cxCaps = (tm.tmPitchAndFamily & 1 ? 3 : 2) * cxChar / 2;
			cyChar = tm.tmHeight + tm.tmExternalLeading;

			ReleaseDC (hwnd, hdc);

			nMaxWidth *= cxChar;
			return 0;

			case WM_SIZE:
			cxClient = LOWORD (lParam);
			cyClient = HIWORD (lParam);

			nVscrollMax = max (0, numlines + 2 - cyClient / cyChar);
			nVscrollPos = min (nVscrollPos, nVscrollMax);

			SetScrollRange (hwnd, SB_VERT, 0, nVscrollMax, false);
			SetScrollPos   (hwnd, SB_VERT, nVscrollPos, true);

			nHscrollMax = max (0, 2 + (nMaxWidth - cxClient) / cxChar);
			nHscrollPos = min (nHscrollPos, nHscrollMax);

			SetScrollRange (hwnd, SB_HORZ, 0, nHscrollMax, false);
			SetScrollPos   (hwnd, SB_HORZ, nHscrollPos, true);
			return 0;

			case WM_VSCROLL:
			switch (LOWORD(wParam))
			{
				case SB_TOP:
				nVscrollInc = -nVscrollPos;
				break ;

				case SB_BOTTOM:
				nVscrollInc = nVscrollMax - nVscrollPos;
				break ;

				case SB_LINEUP:
				nVscrollInc = -1;
				break ;

				case SB_LINEDOWN:
				nVscrollInc = 1;
				break ;

				case SB_PAGEUP:
				nVscrollInc = min (-1, -cyClient / cyChar);
				break ;

				case SB_PAGEDOWN:
				nVscrollInc = max (1, cyClient / cyChar);
				break ;

				case SB_THUMBTRACK:
				nVscrollInc = HIWORD(wParam) - nVscrollPos;
				break ;

				default:
				nVscrollInc = 0;
			}
			nVscrollInc = max (-nVscrollPos,
			min (nVscrollInc, nVscrollMax - nVscrollPos));

			if (nVscrollInc != 0)
			{
				nVscrollPos += nVscrollInc;
				ScrollWindow (hwnd, 0, -cyChar * nVscrollInc, null, null);
				SetScrollPos (hwnd, SB_VERT, nVscrollPos, true);
				UpdateWindow (hwnd);
			}
			return 0;

			case WM_HSCROLL:
			switch (LOWORD(wParam))
			{
				case SB_LINEUP:
				nHscrollInc = -1;
				break ;

				case SB_LINEDOWN:
				nHscrollInc = 1;
				break ;

				case SB_PAGEUP:
				nHscrollInc = -8;
				break ;

				case SB_PAGEDOWN:
				nHscrollInc = 8;
				break ;

				case SB_THUMBTRACK:
				nHscrollInc = HIWORD(wParam) - nHscrollPos;
				break ;

				default:
				nHscrollInc = 0;
			}
			nHscrollInc = max (-nHscrollPos,
			min (nHscrollInc, nHscrollMax - nHscrollPos));

			if (nHscrollInc != 0)
			{
				nHscrollPos += nHscrollInc;
				ScrollWindow (hwnd, -cxChar * nHscrollInc, 0, null, null);
				SetScrollPos (hwnd, SB_HORZ, nHscrollPos, true);
			}
			return 0;

			case WM_KEYDOWN:
			switch (wParam)
			{
				case VK_HOME:
				SendMessageA (hwnd, WM_VSCROLL, SB_TOP, 0L);
				break ;

				case VK_END:
				SendMessageA (hwnd, WM_VSCROLL, SB_BOTTOM, 0L);
				break ;

				case VK_PRIOR:
				SendMessageA (hwnd, WM_VSCROLL, SB_PAGEUP, 0L);
				break ;

				case VK_NEXT:
				SendMessageA (hwnd, WM_VSCROLL, SB_PAGEDOWN, 0L);
				break ;

				case VK_UP:
				SendMessageA (hwnd, WM_VSCROLL, SB_LINEUP, 0L);
				break ;

				case VK_DOWN:
				SendMessageA (hwnd, WM_VSCROLL, SB_LINEDOWN, 0L);
				break ;

				case VK_LEFT:
				SendMessageA (hwnd, WM_HSCROLL, SB_PAGEUP, 0L);
				break ;

				case VK_RIGHT:
				SendMessageA (hwnd, WM_HSCROLL, SB_PAGEDOWN, 0L);
				break ;
				default: // otherwise unknown keystrokes like shift+arrow break the viewer
			}
			return 0;

			case WM_PAINT:
			hdc = BeginPaint (hwnd, &ps);

			SelectObject(hdc, GetStockObject(SYSTEM_FIXED_FONT));

			nPaintBeg = max (0, nVscrollPos + ps.rcPaint.top / cyChar - 1);
			nPaintEnd = min (numlines,
			nVscrollPos + ps.rcPaint.bottom / cyChar);

			p = buffer.ptr;
			int linnum = 0;
			for (i = 0; i < buffer.length; i++)
			{
				if (buffer[i] == '\n')
				{
					if (nPaintBeg <= linnum && linnum < nPaintEnd)
					{
						x = cxChar * (1 - nHscrollPos);
						y = cyChar * (1 - nVscrollPos + linnum);

						int width = &buffer[i] - p;
						if (i && buffer[i - 1] == '\r')
							width--;

						TextOutA(hdc, x, y, p, width);
					}
					linnum++;
					if (i + 1 < buffer.length)
						p = &buffer[i + 1];
				}
			}

			EndPaint (hwnd, &ps);
			return 0;

			case WM_DESTROY:
			//PostQuitMessage (0);
			inhelp--;
			return 0;

			default:
			break ;
		}
	} catch (Exception ignored) {
	}

	return DefWindowProcA(hwnd, message, wParam, lParam);
}
