using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

internal sealed class MainForm : Form
{
    internal const int LauncherVersion = 4;

    const string ManifestUrl = "https://indrolend.github.io/Digital-breakdown-dev/launcher/launcher-manifest.json";
    const string RepoUrl = "https://github.com/indrolend/digital-breakdown-apk.git";
    const string ControllerUrl = "https://indrolend.github.io/Digital-breakdown-dev/dev-control/dev-control.ps1";
    const string AutoStartUrl = "https://indrolend.github.io/Digital-breakdown-dev/dev-control/auto-start.ps1";
    const string AppId = "com.indrolend.digitalbreakdown.native";
    const string Activity = "com.indrolend.digitalbreakdown.MainActivity";

    readonly string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DigitalBreakdownDev");
    readonly string launcherRoot;
    readonly string controlRoot;
    readonly string repo;
    readonly string controller;
    readonly string autoStart;
    readonly string installedState;
    readonly string desktopState;

    readonly Label githubValue = ValueLabel();
    readonly Label cacheValue = ValueLabel();
    readonly Label desktopValue = ValueLabel();
    readonly Label phoneValue = ValueLabel();
    readonly Label statusValue = ValueLabel();
    readonly Label note = new Label();
    readonly Button desktopButton = MainButton("RUN DESKTOP DEV BUILD");
    readonly Button streamButton = MainButton("STREAM FROM STYLO 4");
    readonly Button refreshButton = new Button();

    string adb;
    string serial;
    bool busy;

    public MainForm()
    {
        launcherRoot = Path.Combine(root, "launcher");
        controlRoot = Path.Combine(root, "control");
        repo = Path.Combine(root, "source");
        controller = Path.Combine(controlRoot, "dev-control.ps1");
        autoStart = Path.Combine(controlRoot, "auto-start.ps1");
        installedState = Path.Combine(root, "installed-build.json");
        desktopState = Path.Combine(root, "desktop-build.json");

        Text = "Digital Breakdown";
        ClientSize = new Size(480, 700);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        BackColor = Color.FromArgb(10,10,10);
        ForeColor = Color.Gainsboro;
        Font = new Font("Consolas", 9.5f);
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);

        BuildUi();
        Shown += async (s,e) => await StartupAsync();
    }

    static Label ValueLabel() => new Label { Text="—", TextAlign=ContentAlignment.MiddleRight };
    static Button MainButton(string text) => new Button { Text=text, FlatStyle=FlatStyle.Flat, Font=new Font("Consolas",13f,FontStyle.Bold) };

    void BuildUi()
    {
        var art = new PictureBox { Bounds=new Rectangle(150,18,180,180), SizeMode=PictureBoxSizeMode.Zoom, BackColor=Color.Black };
        string artPath = Path.Combine(launcherRoot, "Digital-Breakdown-Art.png");
        if (File.Exists(artPath)) art.Image = Image.FromFile(artPath);
        Controls.Add(art);
        Controls.Add(new Label { Text="DIGITAL BREAKDOWN", Font=new Font("Consolas",18f,FontStyle.Bold), TextAlign=ContentAlignment.MiddleCenter, Bounds=new Rectangle(35,205,410,42) });

        AddRow("GITHUB MAIN", githubValue, 265);
        AddRow("SOURCE CACHE", cacheValue, 299);
        AddRow("DESKTOP BUILD", desktopValue, 333);
        AddRow("STYLO 4 BUILD", phoneValue, 367);
        AddRow("STATUS", statusValue, 401);

        desktopButton.Bounds = new Rectangle(65,455,350,56);
        streamButton.Bounds = new Rectangle(65,525,350,56);
        refreshButton.Text = "CHECK FOR UPDATES";
        refreshButton.FlatStyle = FlatStyle.Flat;
        refreshButton.Bounds = new Rectangle(150,595,180,34);
        note.TextAlign = ContentAlignment.MiddleCenter;
        note.ForeColor = Color.DarkGray;
        note.Bounds = new Rectangle(35,638,410,40);

        Controls.Add(desktopButton);
        Controls.Add(streamButton);
        Controls.Add(refreshButton);
        Controls.Add(note);

        desktopButton.Click += async (s,e) => await RunDesktopAsync();
        streamButton.Click += async (s,e) => await StreamAsync();
        refreshButton.Click += async (s,e) => await UpdateEverythingAsync();
    }

    void AddRow(string key, Label value, int y)
    {
        Controls.Add(new Label { Text=key, ForeColor=Color.DarkGray, Bounds=new Rectangle(55,y,170,26) });
        value.Bounds = new Rectangle(225,y,200,26);
        Controls.Add(value);
    }

    async Task StartupAsync()
    {
        if (busy) return;
        busy = true;
        Toggle(false);
        try
        {
            if (await TrySelfUpdateAsync()) return;
            Directory.CreateDirectory(controlRoot);
            await Task.Run(() => {
                DownloadValidated(ControllerUrl, controller, "DIGITAL BREAKDOWN DEV CONTROL");
                DownloadValidated(AutoStartUrl, autoStart, "UPDATE_REQUIRED");
            });
            await RefreshAsync();
        }
        catch (Exception ex) { SetStatus("DEGRADED", ex.Message); }
        finally { busy = false; Toggle(true); }
    }

    async Task<bool> TrySelfUpdateAsync()
    {
        try
        {
            SetStatus("CHECKING", "Checking launcher version…");
            string manifest = await DownloadTextAsync(ManifestUrl);
            int version = Int32.Parse(Regex.Match(manifest, "\"version\"\\s*:\\s*(\\d+)").Groups[1].Value);
            if (version <= LauncherVersion) return false;

            string sourceUrl = Regex.Match(manifest, "\"sourceUrl\"\\s*:\\s*\"([^\"]+)\"").Groups[1].Value;
            if (String.IsNullOrWhiteSpace(sourceUrl)) throw new InvalidDataException("Launcher manifest has no source URL.");

            SetStatus("UPDATING LAUNCHER", "Compiling launcher version " + version + "…");
            string updateDir = Path.Combine(root, "launcher-update");
            Directory.CreateDirectory(updateDir);
            string source = Path.Combine(updateDir, "DigitalBreakdownLauncher.cs");
            string replacement = Path.Combine(updateDir, "Digital-Breakdown.exe");
            string icon = Path.Combine(launcherRoot, "Digital-Breakdown.ico");
            File.WriteAllText(source, await DownloadTextAsync(sourceUrl), new UTF8Encoding(false));

            string sourceText = File.ReadAllText(source);
            if (!sourceText.Contains("internal const int LauncherVersion = " + version + ";"))
                throw new InvalidDataException("Downloaded launcher source failed version validation.");

            string csc = ResolveCsc();
            string args = "/nologo /target:winexe /platform:anycpu /reference:System.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll ";
            if (File.Exists(icon)) args += "/win32icon:\"" + icon + "\" ";
            args += "/out:\"" + replacement + "\" \"" + source + "\"";
            await RunCaptureAsync(csc, args, false);
            if (!File.Exists(replacement)) throw new FileNotFoundException("Replacement launcher was not produced.");

            string current = Application.ExecutablePath;
            string updater = Path.Combine(updateDir, "apply-update.cmd");
            string script = "@echo off\r\n" +
                "setlocal\r\n" +
                ":wait\r\n" +
                "tasklist /FI \"PID eq " + Process.GetCurrentProcess().Id + "\" | find \"" + Process.GetCurrentProcess().Id + "\" >nul\r\n" +
                "if not errorlevel 1 (timeout /t 1 /nobreak >nul & goto wait)\r\n" +
                "if exist \"" + current + ".previous\" del /q \"" + current + ".previous\"\r\n" +
                "move /y \"" + current + "\" \"" + current + ".previous\" >nul\r\n" +
                "move /y \"" + replacement + "\" \"" + current + "\" >nul\r\n" +
                "if errorlevel 1 (move /y \"" + current + ".previous\" \"" + current + "\" >nul & exit /b 1)\r\n" +
                "del /q \"" + current + ".previous\" >nul 2>&1\r\n" +
                "start \"\" \"" + current + "\"\r\n" +
                "exit /b 0\r\n";
            File.WriteAllText(updater, script, Encoding.ASCII);
            Process.Start(new ProcessStartInfo { FileName=updater, UseShellExecute=true, WindowStyle=ProcessWindowStyle.Hidden });
            BeginInvoke(new Action(Close));
            return true;
        }
        catch
        {
            return false;
        }
    }

    async Task UpdateEverythingAsync()
    {
        if (busy) return;
        busy = true;
        Toggle(false);
        try
        {
            if (await TrySelfUpdateAsync()) return;
            await SyncSourceAsync();
            await RefreshAsync();
            SetStatus("READY", "Launcher and game source are current.");
        }
        catch (Exception ex) { SetStatus("FAILED", ex.Message); }
        finally { busy = false; Toggle(true); }
    }

    async Task SyncSourceAsync()
    {
        string git = FindExecutable("git.exe");
        if (git == null) throw new InvalidOperationException("Git for Windows was not found.");
        Directory.CreateDirectory(root);

        if (!Directory.Exists(Path.Combine(repo, ".git")))
        {
            if (Directory.Exists(repo) && Directory.GetFileSystemEntries(repo).Length > 0)
                throw new InvalidOperationException("Managed source exists but is not a Git repository.");
            SetStatus("RETRIEVING", "Cloning authoritative GitHub source…");
            await RunCaptureAsync(git, "clone \"" + RepoUrl + "\" \"" + repo + "\"", false);
            return;
        }

        string dirty = await RunCaptureAsync(git, "-C \"" + repo + "\" status --porcelain", false);
        if (!String.IsNullOrWhiteSpace(dirty))
            throw new InvalidOperationException("Source cache has local edits. Update stopped without overwriting them.");

        SetStatus("UPDATING", "Fast-forwarding source to GitHub main…");
        await RunCaptureAsync(git, "-C \"" + repo + "\" fetch origin main --prune", false);
        await RunCaptureAsync(git, "-C \"" + repo + "\" checkout main", false);
        await RunCaptureAsync(git, "-C \"" + repo + "\" pull --ff-only origin main", false);
    }

    async Task RunDesktopAsync()
    {
        if (busy) return;
        busy = true;
        Toggle(false);
        try
        {
            await SyncSourceAsync();
            string script = Path.Combine(repo, "tools", "desktop", "run-desktop.ps1");
            if (!File.Exists(script)) throw new FileNotFoundException("Desktop build script is missing.", script);
            SetStatus("BUILDING DESKTOP", "Building latest GitHub revision…");
            await RunCaptureAsync("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"", false);
            WriteDesktopState(GetLocalRevision() ?? "unknown");
            SetStatus("RUNNING DESKTOP", "Desktop development build launched.");
            await RefreshAsync();
        }
        catch (Exception ex) { SetStatus("FAILED", ex.Message); }
        finally { busy = false; Toggle(true); }
    }

    async Task StreamAsync()
    {
        if (busy) return;
        busy = true;
        Toggle(false);
        try
        {
            await SyncSourceAsync();
            if (!File.Exists(autoStart)) throw new FileNotFoundException("Android startup helper is missing.");
            SetStatus("PREPARING ANDROID", "Checking, building, and installing current revision…");
            await RunCaptureAsync("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File \"" + autoStart + "\"", false);
            await RefreshAsync();
            if (String.IsNullOrEmpty(serial)) throw new InvalidOperationException("No authorized Stylo 4 is connected.");
            await RunCaptureAsync(adb, "-s " + serial + " shell am start -W -n " + AppId + "/" + Activity, false);
            string scrcpy = ResolveScrcpy();
            if (scrcpy == null) throw new InvalidOperationException("scrcpy was not found.");
            var process = Process.Start(new ProcessStartInfo { FileName=scrcpy, Arguments="-s " + serial + " --max-size=1024 --video-bit-rate=4M --stay-awake --no-audio --window-title=\"Digital Breakdown\"", UseShellExecute=false });
            Hide();
            await Task.Run(() => process.WaitForExit());
            Show(); Activate();
            await RefreshAsync();
        }
        catch (Exception ex) { Show(); SetStatus("FAILED", ex.Message); }
        finally { busy = false; Toggle(true); }
    }

    async Task RefreshAsync()
    {
        githubValue.Text = await GetRemoteRevisionAsync();
        cacheValue.Text = GetLocalRevision() ?? "NOT RETRIEVED";
        desktopValue.Text = JsonRevision(desktopState) ?? "UNBUILT";
        phoneValue.Text = JsonRevision(installedState) ?? "UNKNOWN";

        adb = ResolveAdb(); serial = null;
        if (adb == null) { SetStatus("ADB MISSING", "Desktop development remains available."); return; }
        string devices = await RunCaptureAsync(adb, "devices", true);
        Match m = Regex.Match(devices, @"(?m)^([^\s]+)\s+device\s*$");
        if (!m.Success) { SetStatus("PHONE DISCONNECTED", "Desktop development remains available."); return; }
        serial = m.Groups[1].Value.Trim();
        bool installed = (await RunCaptureAsync(adb, "-s " + serial + " shell pm path " + AppId, true)).Contains("package:");
        SetStatus(installed ? "READY" : "ANDROID UPDATE REQUIRED", installed ? "Desktop and Stylo 4 workflows available." : "Stream from Stylo 4 will install the current build.");
    }

    void SetStatus(string state, string detail)
    {
        statusValue.Text = state; note.Text = detail;
        statusValue.ForeColor = state.Contains("READY") || state.Contains("RUNNING") ? Color.LightGreen : state.Contains("FAILED") || state.Contains("MISSING") || state.Contains("DISCONNECTED") ? Color.IndianRed : Color.Khaki;
    }

    void Toggle(bool enabled)
    {
        desktopButton.Enabled = enabled;
        streamButton.Enabled = enabled;
        refreshButton.Enabled = enabled;
    }

    async Task<string> GetRemoteRevisionAsync()
    {
        try
        {
            string git = FindExecutable("git.exe");
            if (git == null) return "GIT MISSING";
            string output = await RunCaptureAsync(git, "ls-remote \"" + RepoUrl + "\" refs/heads/main", true);
            Match m = Regex.Match(output, @"^([0-9a-fA-F]{7,40})");
            return m.Success ? Short(m.Groups[1].Value) : "UNAVAILABLE";
        }
        catch { return "UNAVAILABLE"; }
    }

    string GetLocalRevision()
    {
        try
        {
            if (!Directory.Exists(Path.Combine(repo, ".git"))) return null;
            string git = FindExecutable("git.exe");
            var p = Process.Start(new ProcessStartInfo { FileName=git, Arguments="-C \"" + repo + "\" rev-parse --short HEAD", UseShellExecute=false, RedirectStandardOutput=true, CreateNoWindow=true });
            string output = p.StandardOutput.ReadToEnd().Trim(); p.WaitForExit();
            return p.ExitCode == 0 ? output : null;
        }
        catch { return null; }
    }

    void WriteDesktopState(string revision)
    {
        File.WriteAllText(desktopState, "{\n  \"shortCommit\": \"" + revision.Replace("\"","") + "\",\n  \"builtAt\": \"" + DateTime.Now.ToString("o") + "\"\n}", Encoding.UTF8);
    }

    static string JsonRevision(string path)
    {
        try
        {
            if (!File.Exists(path)) return null;
            Match m = Regex.Match(File.ReadAllText(path), "\"shortCommit\"\\s*:\\s*\"([^\"]+)\"");
            return m.Success ? m.Groups[1].Value : null;
        }
        catch { return null; }
    }

    static async Task<string> DownloadTextAsync(string url)
    {
        using (var client = new WebClient())
            return await client.DownloadStringTaskAsync(url + "?t=" + DateTimeOffset.UtcNow.ToUnixTimeSeconds());
    }

    static void DownloadValidated(string url, string target, string marker)
    {
        try
        {
            string temp = target + ".download";
            using (var client = new WebClient()) client.DownloadFile(url + "?t=" + DateTimeOffset.UtcNow.ToUnixTimeSeconds(), temp);
            string text = File.ReadAllText(temp, Encoding.UTF8);
            if (!text.Contains(marker)) throw new InvalidDataException("Downloaded service failed validation.");
            File.WriteAllText(temp, text, new UTF8Encoding(false));
            if (File.Exists(target)) File.Delete(target);
            File.Move(temp, target);
        }
        catch { if (!File.Exists(target)) throw; }
    }

    static async Task<string> RunCaptureAsync(string file, string args, bool ignoreExit)
    {
        return await Task.Run(() => {
            var start = new ProcessStartInfo { FileName=file, Arguments=args, UseShellExecute=false, RedirectStandardOutput=true, RedirectStandardError=true, CreateNoWindow=true };
            using (var process = Process.Start(start))
            {
                string output = process.StandardOutput.ReadToEnd();
                string error = process.StandardError.ReadToEnd();
                process.WaitForExit();
                string combined = output + (String.IsNullOrWhiteSpace(error) ? "" : Environment.NewLine + error);
                if (!ignoreExit && process.ExitCode != 0) throw new InvalidOperationException(String.IsNullOrWhiteSpace(combined) ? file + " exited with code " + process.ExitCode : combined.Trim());
                return combined;
            }
        });
    }

    static string ResolveCsc()
    {
        string a = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Microsoft.NET", "Framework64", "v4.0.30319", "csc.exe");
        string b = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Microsoft.NET", "Framework", "v4.0.30319", "csc.exe");
        if (File.Exists(a)) return a;
        if (File.Exists(b)) return b;
        throw new FileNotFoundException("Microsoft C# compiler was not found.");
    }

    static string ResolveAdb()
    {
        string found = FindExecutable("adb.exe");
        if (found != null) return found;
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string p = Path.Combine(local,"Android","Sdk","platform-tools","adb.exe");
        return File.Exists(p) ? p : null;
    }

    string ResolveScrcpy()
    {
        string found = FindExecutable("scrcpy.exe");
        if (found != null) return found;
        string profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        string p = Path.Combine(profile,"scrcpy","scrcpy.exe");
        return File.Exists(p) ? p : null;
    }

    static string FindExecutable(string name)
    {
        string env = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (string dir in env.Split(';'))
        {
            try { string candidate = Path.Combine(dir.Trim(), name); if (File.Exists(candidate)) return candidate; }
            catch { }
        }
        return null;
    }

    static string Short(string value) => value.Trim().Length > 7 ? value.Trim().Substring(0,7) : value.Trim();
}

internal static class Program
{
    [STAThread]
    static void Main()
    {
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new MainForm());
    }
}
