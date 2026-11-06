using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;

static class Program
{
    static int Main()
    {
        Console.Title = "Right-click File Converter Setup";
        string dir = Path.Combine(Path.GetTempPath(), "RCC_" + Guid.NewGuid().ToString("N"));
        int code = 1;
        try
        {
            Directory.CreateDirectory(dir);
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            using (ZipArchive za = new ZipArchive(s, ZipArchiveMode.Read))
            {
                foreach (ZipArchiveEntry e in za.Entries)
                {
                    string name = Path.GetFileName(e.FullName);
                    if (name.Length == 0) continue;
                    e.ExtractToFile(Path.Combine(dir, name), true);
                }
            }
            ProcessStartInfo psi = new ProcessStartInfo("cmd.exe", "/c \"" + Path.Combine(dir, "Install.bat") + "\"");
            psi.WorkingDirectory = dir;
            psi.UseShellExecute = false;
            using (Process p = Process.Start(psi))
            {
                p.WaitForExit();
                code = p.ExitCode;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("Setup failed: " + ex.Message);
            Console.WriteLine("Press Enter to close.");
            Console.ReadLine();
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch { }
        }
        return code;
    }
}
