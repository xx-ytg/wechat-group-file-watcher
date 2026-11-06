param([Parameter(Mandatory)][string]$Executable,
      [Parameter(Mandatory)][string]$Arguments)
$ErrorActionPreference = 'Stop'
# Use a duplicated token with the same identity and privileges. Only its default
# file owner changes, so SQLite-created companion files belong to the user.
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
public static class PrivateProcess {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  struct STARTUPINFO {
    public int cb; public string reserved, desktop, title;
    public int x,y,xsize,ysize,xchars,ychars,fill,flags;
    public short show,reserved2; public IntPtr reservedPtr,input,output,error;
  }
  [StructLayout(LayoutKind.Sequential)]
  struct PROCESSINFO { public IntPtr process,thread; public uint pid,tid; }
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("advapi32.dll", SetLastError=true)]
  static extern bool OpenProcessToken(IntPtr p,uint access,out IntPtr token);
  [DllImport("advapi32.dll", SetLastError=true)]
  static extern bool DuplicateTokenEx(IntPtr token,uint access,IntPtr attr,int level,int type,out IntPtr result);
  [DllImport("advapi32.dll", SetLastError=true)]
  static extern bool SetTokenInformation(IntPtr token,int kind,IntPtr value,int length);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern bool CreateProcessWithTokenW(IntPtr token,uint logon,string app,StringBuilder cmd,uint flags,IntPtr env,string cwd,ref STARTUPINFO startup,out PROCESSINFO process);
  static void Check(bool ok) { if(!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
  public static uint Start(string exe,string args) {
    IntPtr source=IntPtr.Zero,child=IntPtr.Zero,sid=IntPtr.Zero,owner=IntPtr.Zero;
    try {
      Check(OpenProcessToken(GetCurrentProcess(),10,out source));
      Check(DuplicateTokenEx(source,0x02000000,IntPtr.Zero,2,1,out child));
      var user=WindowsIdentity.GetCurrent().User;
      byte[] bytes=new byte[user.BinaryLength]; user.GetBinaryForm(bytes,0);
      sid=Marshal.AllocHGlobal(bytes.Length); Marshal.Copy(bytes,0,sid,bytes.Length);
      owner=Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(owner,sid);
      Check(SetTokenInformation(child,4,owner,IntPtr.Size));
      STARTUPINFO startup=new STARTUPINFO(); startup.cb=Marshal.SizeOf(startup);
      PROCESSINFO process;
      Check(CreateProcessWithTokenW(child,0,exe,new StringBuilder("\""+exe+"\" "+args),0x08000000,IntPtr.Zero,System.IO.Path.GetDirectoryName(exe),ref startup,out process));
      CloseHandle(process.thread); CloseHandle(process.process); return process.pid;
    } finally {
      if(owner!=IntPtr.Zero) Marshal.FreeHGlobal(owner);
      if(sid!=IntPtr.Zero) Marshal.FreeHGlobal(sid);
      if(child!=IntPtr.Zero) CloseHandle(child);
      if(source!=IntPtr.Zero) CloseHandle(source);
    }
  }
}
'@
[PrivateProcess]::Start((Resolve-Path -LiteralPath $Executable).Path,$Arguments)
