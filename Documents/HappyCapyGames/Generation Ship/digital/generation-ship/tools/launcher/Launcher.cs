// Steam starts this as GS.exe: it runs the real game (GS_game.exe, next to it) and stays invisible.
// Only when the game ends with an error (a crash, a graphics driver failing during start-up)
// does it show a small window with steps that fit the case: safe graphics mode (Godot's OpenGL
// renderer, remembered in the file "safe_graphics" in the game's user folder), the right driver
// download page for the graphics card, Visual C++ for a missing DLL, the log folder, and, if the
// player ticks it, an error report to api.happycapygames.com/v1/crashes (server/app/crashes.py).
// Built by tools/release.py with the C# compiler that ships with Windows (.NET Framework 4).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Management;
using System.Net;
using System.Text;
using System.Windows.Forms;

static class Launcher
{
    const string GameExe = "GS_game.exe";
    const string SafeArgs = "--rendering-method gl_compatibility --rendering-driver opengl3";
    const int StartSeconds = 60;   // an error exit sooner than this counts as "while starting"
    const string ReportUrl = "https://api.happycapygames.com/v1/crashes";
    const string VcRedistUrl = "https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist";

    static readonly string UserDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Godot", "app_userdata", "Generation Ship");
    static readonly string SafeFlag = Path.Combine(UserDir, "safe_graphics");
    static readonly string SendFlag = Path.Combine(UserDir, "send_error_reports");
    static readonly string GameDir = AppDomain.CurrentDomain.BaseDirectory;

    [STAThread]
    static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        string game = Path.Combine(GameDir, GameExe);
        Strings s = Strings.For(Locale());
        if (!File.Exists(game))
        {
            MessageBox.Show(s.Missing, "Generation Ship", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        if (File.Exists(SafeFlag) && ReadSmall(SafeFlag) != "quiet")
            AskSafeOnStart(s);
        while (true)
        {
            bool safe = File.Exists(SafeFlag);
            var psi = new ProcessStartInfo(game, (safe ? SafeArgs + " " : "") + JoinArgs(args));
            psi.UseShellExecute = false;
            psi.WorkingDirectory = GameDir;
            DateTime t0 = DateTime.Now;
            int code;
            try
            {
                using (Process p = Process.Start(psi))
                {
                    p.WaitForExit();
                    code = p.ExitCode;
                }
            }
            catch (Exception e)
            {
                MessageBox.Show(s.Missing + "\n\n" + e.Message, "Generation Ship", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
            if (code == 0)
                return 0;
            bool starting = (DateTime.Now - t0).TotalSeconds < StartSeconds;
            List<Gpu> gpus = Gpus();
            bool send;
            Choice c = Ask(s, code, starting, safe, gpus, out send);
            SetFlag(SendFlag, send);
            if (send)
                SendReport(code, starting, safe, gpus);
            if (c == Choice.Close)
                return code;
            if (c == Choice.SafeMode)
                SetFlag(SafeFlag, true);
            else if (c == Choice.NormalMode)
                SetFlag(SafeFlag, false);
        }
    }

    static void SetFlag(string path, bool on)
    {
        try
        {
            if (on) { Directory.CreateDirectory(UserDir); File.WriteAllText(path, "1"); }
            else if (File.Exists(path)) File.Delete(path);
        }
        catch (Exception) { }
    }

    // the game's own language (settings.cfg [game] locale="de"), else Windows' language
    static string Locale()
    {
        try
        {
            foreach (string line in File.ReadAllLines(Path.Combine(UserDir, "settings.cfg")))
            {
                string t = line.Trim();
                if (t.StartsWith("locale="))
                    return t.Substring(7).Trim('"', ' ');
            }
        }
        catch (Exception) { }
        return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
    }

    // command-line arguments passed through to the game, quoted the Windows way
    static string JoinArgs(string[] args)
    {
        var sb = new StringBuilder();
        foreach (string a in args)
        {
            if (sb.Length > 0) sb.Append(' ');
            if (a.Length > 0 && a.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) { sb.Append(a); continue; }
            sb.Append('"');
            int slashes = 0;
            foreach (char ch in a)
            {
                if (ch == '\\') { slashes++; continue; }
                if (ch == '"') sb.Append('\\', slashes * 2 + 1);
                else sb.Append('\\', slashes);
                slashes = 0;
                sb.Append(ch);
            }
            sb.Append('\\', slashes * 2).Append('"');
        }
        return sb.ToString();
    }

    // ── Graphics cards ──────────────────────────────────────────────────────

    class Gpu { public string Name = "", Driver = "", Vendor = ""; }

    static List<Gpu> Gpus()
    {
        var list = new List<Gpu>();
        try
        {
            using (var q = new ManagementObjectSearcher("SELECT Name, DriverVersion, AdapterCompatibility FROM Win32_VideoController"))
                foreach (ManagementObject o in q.Get())
                {
                    var g = new Gpu { Name = Str(o["Name"]), Driver = Str(o["DriverVersion"]) };
                    string all = (g.Name + " " + Str(o["AdapterCompatibility"])).ToLowerInvariant();
                    g.Vendor = all.Contains("nvidia") ? "nvidia" : all.Contains("amd") || all.Contains("radeon") || all.Contains("advanced micro") ? "amd"
                        : all.Contains("intel") ? "intel" : "";
                    if (g.Name.Length > 0) list.Add(g);
                }
        }
        catch (Exception) { }
        return list;
    }

    static string Str(object o) { return o == null ? "" : o.ToString().Trim(); }

    // the card that most likely runs the game: a dedicated NVIDIA/AMD one before Intel or unknown
    static Gpu MainGpu(List<Gpu> gpus)
    {
        foreach (Gpu g in gpus) if (g.Vendor == "nvidia" || g.Vendor == "amd") return g;
        foreach (Gpu g in gpus) if (g.Vendor == "intel") return g;
        return gpus.Count > 0 ? gpus[0] : null;
    }

    static string DriverUrl(Gpu g)
    {
        switch (g == null ? "" : g.Vendor)
        {
            case "nvidia": return "https://www.nvidia.com/drivers/";
            case "amd": return "https://www.amd.com/en/support/download/drivers.html";
            case "intel": return "https://www.intel.com/content/www/us/en/support/detect.html";
            default: return "ms-settings:windowsupdate";
        }
    }

    static bool TwoChips(List<Gpu> gpus)
    {
        bool intel = false, dedicated = false;
        foreach (Gpu g in gpus)
        {
            if (g.Vendor == "intel") intel = true;
            if (g.Vendor == "nvidia" || g.Vendor == "amd") dedicated = true;
        }
        return intel && dedicated;
    }

    // exit codes of a missing / broken DLL or Windows component
    static bool DllProblem(int code)
    {
        uint c = unchecked((uint)code);
        return c == 0xC0000135 || c == 0xC0000139 || c == 0xC000007B || c == 0xC0000142;
    }

    static void Open(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch (Exception) { }
    }

    // ── Start-up question while safe graphics mode is on ───────────────────
    // (after a driver update normal graphics often work again; "don't ask again" keeps safe mode
    // quietly: the flag file then holds "quiet" instead of "1")

    static void AskSafeOnStart(Strings s)
    {
        var form = NewForm();
        var layout = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false, Location = new Point(16, 16) };
        layout.Controls.Add(new Label { Text = s.SafeOnStart, AutoSize = true, MaximumSize = new Size(520, 0), Margin = new Padding(0, 0, 0, 12) });
        var quiet = new CheckBox { Text = s.DontAsk, AutoSize = true, Margin = new Padding(0, 0, 0, 12) };
        layout.Controls.Add(quiet);
        var row = new FlowLayoutPanel { FlowDirection = FlowDirection.LeftToRight, AutoSize = true, WrapContents = true, MaximumSize = new Size(560, 0), Margin = new Padding(0) };
        bool normal = false;
        var keep = new Button { Text = s.KeepSafe, AutoSize = true, Padding = new Padding(8, 2, 8, 2) };
        keep.Click += (o, e) => form.Close();
        var tryNormal = new Button { Text = s.TryNormal, AutoSize = true, Padding = new Padding(8, 2, 8, 2) };
        tryNormal.Click += (o, e) => { normal = true; form.Close(); };
        row.Controls.Add(keep);
        row.Controls.Add(tryNormal);
        layout.Controls.Add(row);
        form.AcceptButton = keep;
        form.Controls.Add(layout);
        form.ShowDialog();
        if (normal)
            SetFlag(SafeFlag, false);
        else if (quiet.Checked)
            try { File.WriteAllText(SafeFlag, "quiet"); } catch (Exception) { }
    }

    static Form NewForm()
    {
        var form = new Form
        {
            Text = "Generation Ship",
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false, MinimizeBox = false,
            StartPosition = FormStartPosition.CenterScreen,
            AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Padding = new Padding(0, 0, 16, 16), TopMost = true,
            Font = SystemFonts.MessageBoxFont,
        };
        try { form.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }
        return form;
    }

    // ── Crash window ────────────────────────────────────────────────────────

    enum Choice { Close, Restart, SafeMode, NormalMode }

    static Choice Ask(Strings s, int code, bool starting, bool safe, List<Gpu> gpus, out bool send)
    {
        Choice result = Choice.Close;
        Gpu gpu = MainGpu(gpus);
        string card = gpu != null ? gpu.Name : s.YourCard;
        bool dll = DllProblem(code);
        string msg;
        if (dll) msg = s.DllMissing;
        else if (!starting) msg = string.Format(s.Closed, card);
        else if (safe) msg = string.Format(s.SafeFailed, card);
        else msg = string.Format(s.StartFailed, card) + (TwoChips(gpus) ? "\n" + s.Laptop : "");

        var form = NewForm();
        var layout = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false, Location = new Point(16, 16) };
        layout.Controls.Add(new Label { Text = msg, AutoSize = true, MaximumSize = new Size(520, 0), Margin = new Padding(0, 0, 0, 8) });
        layout.Controls.Add(new Label { Text = s.Code + ": 0x" + code.ToString("X8"), AutoSize = true, ForeColor = SystemColors.GrayText, Margin = new Padding(0, 0, 0, 10) });
        // a CheckBox doesn't wrap its text by itself: fixed width, height measured for the wrapped text
        int textH = TextRenderer.MeasureText(s.Send, form.Font, new Size(496, 0), TextFormatFlags.WordBreak).Height;
        var report = new CheckBox { Text = s.Send, AutoSize = false, Size = new Size(520, textH + 6), CheckAlign = ContentAlignment.TopLeft,
            TextAlign = ContentAlignment.TopLeft, Checked = File.Exists(SendFlag), Margin = new Padding(0, 0, 0, 12) };
        layout.Controls.Add(report);

        var row1 = new FlowLayoutPanel { FlowDirection = FlowDirection.LeftToRight, AutoSize = true, WrapContents = true, MaximumSize = new Size(560, 0), Margin = new Padding(0) };
        var row2 = new FlowLayoutPanel { FlowDirection = FlowDirection.LeftToRight, AutoSize = true, WrapContents = true, MaximumSize = new Size(560, 0), Margin = new Padding(0) };
        Func<FlowLayoutPanel, string, Button> button = (row, text) =>
        {
            var b = new Button { Text = text, AutoSize = true, Padding = new Padding(8, 2, 8, 2) };
            row.Controls.Add(b);
            return b;
        };
        Action<FlowLayoutPanel, string, Choice> choice = (row, text, ch) =>
        {
            Button b = button(row, text);
            b.Click += (o, e) => { result = ch; form.Close(); };
            if (form.AcceptButton == null) form.AcceptButton = b;
        };
        if (dll)
        {
            choice(row1, s.Restart, Choice.Restart);
            button(row1, s.VcRedist).Click += (o, e) => Open(VcRedistUrl);
        }
        else
        {
            if (starting && !safe) choice(row1, s.Safe, Choice.SafeMode);
            else if (starting) choice(row1, s.Normal, Choice.NormalMode);
            else
            {
                choice(row1, s.Restart, Choice.Restart);
                if (!safe) choice(row1, s.RestartSafe, Choice.SafeMode);
            }
            button(row1, s.Driver).Click += (o, e) => Open(DriverUrl(gpu));
        }
        button(row2, s.Logs).Click += (o, e) =>
        {
            string dir = Path.Combine(UserDir, "logs");
            if (!Directory.Exists(dir)) dir = Directory.Exists(UserDir) ? UserDir : Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            try { Process.Start("explorer.exe", "\"" + dir + "\""); } catch (Exception) { }
        };
        choice(row2, s.Close, Choice.Close);
        layout.Controls.Add(row1);
        layout.Controls.Add(row2);
        form.Controls.Add(layout);
        form.ShowDialog();
        send = report.Checked;
        return result;
    }

    // ── Error report ────────────────────────────────────────────────────────

    static void SendReport(int code, bool starting, bool safe, List<Gpu> gpus)
    {
        try
        {
            var gpuText = new List<string>();
            foreach (Gpu g in gpus) gpuText.Add(g.Name + (g.Driver.Length > 0 ? " (driver " + g.Driver + ")" : ""));
            string json = "{" +
                Pair("install", InstallId()) + "," +
                Pair("build", ReadSmall(Path.Combine(GameDir, "build.txt"))) + "," +
                Pair("exit_code", "0x" + code.ToString("X8")) + "," +
                Pair("phase", starting ? "start" : "play") + "," +
                "\"safe_mode\":" + (safe ? "true" : "false") + "," +
                Pair("os", WindowsVersion()) + "," +
                Pair("gpu", Cut(string.Join("; ", gpuText.ToArray()), 400)) + "," +
                Pair("log", LogTail()) + "}";
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;   // TLS 1.2
            var req = (HttpWebRequest)WebRequest.Create(ReportUrl);
            req.Method = "POST";
            req.ContentType = "application/json";
            req.Timeout = 8000;
            byte[] body = Encoding.UTF8.GetBytes(json);
            using (Stream st = req.GetRequestStream()) st.Write(body, 0, body.Length);
            using (req.GetResponse()) { }
        }
        catch (Exception) { }   // offline or server down: never bother the player about it
    }

    static string InstallId()
    {
        string path = Path.Combine(UserDir, "install_id");
        try
        {
            string id = ReadSmall(path);
            if (id.Length >= 16) return id;
            id = Guid.NewGuid().ToString();
            Directory.CreateDirectory(UserDir);
            File.WriteAllText(path, id);
            return id;
        }
        catch (Exception) { return Guid.NewGuid().ToString(); }
    }

    static string ReadSmall(string path)
    {
        try { return File.Exists(path) ? Cut(File.ReadAllText(path).Trim(), 64) : ""; } catch (Exception) { return ""; }
    }

    static string WindowsVersion()
    {
        try
        {
            using (var k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
            {
                string name = Str(k.GetValue("ProductName")), disp = Str(k.GetValue("DisplayVersion")), build = Str(k.GetValue("CurrentBuild"));
                int b;
                if (int.TryParse(build, out b) && b >= 22000) name = name.Replace("Windows 10", "Windows 11");   // the registry still says 10
                return Cut(name + " " + disp + " (build " + build + ")", 200);
            }
        }
        catch (Exception) { return Environment.OSVersion.VersionString; }
    }

    // the end of this run's godot.log, with the Windows user and PC name taken out
    static string LogTail()
    {
        try
        {
            string path = Path.Combine(UserDir, "logs", "godot.log");
            string text;
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var r = new StreamReader(fs, Encoding.UTF8))
                text = r.ReadToEnd();
            if (text.Length > 60000) text = text.Substring(text.Length - 60000);
            foreach (string secret in new[] { Environment.UserName, Environment.MachineName })
                if (!string.IsNullOrEmpty(secret) && secret.Length > 1)
                    text = text.Replace(secret, "<user>");
            return text;
        }
        catch (Exception) { return ""; }
    }

    static string Cut(string s, int n) { return s.Length > n ? s.Substring(0, n) : s; }

    static string Pair(string key, string value)
    {
        var sb = new StringBuilder("\"" + key + "\":\"");
        foreach (char ch in value)
        {
            switch (ch)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (ch < 0x20) sb.Append("\\u").Append(((int)ch).ToString("x4"));
                    else sb.Append(ch);
                    break;
            }
        }
        return sb.Append('"').ToString();
    }
}

// {0} in the messages = the graphics card's name
class Strings
{
    public string StartFailed, SafeFailed, Closed, Laptop, DllMissing, YourCard;
    public string Safe, Normal, Restart, RestartSafe, Driver, VcRedist, Logs, Close, Code, Send, Missing;
    public string SafeOnStart, KeepSafe, TryNormal, DontAsk;

    public static Strings For(string locale)
    {
        switch ((locale ?? "").ToLowerInvariant().Split('_', '-')[0])
        {
            case "de": return new Strings
            {
                StartFailed = "Generation Ship wurde beim Starten beendet. Fast immer liegt das am Grafiktreiber.\n\nSo kannst du es beheben:\n1. Klicke auf „Im sicheren Grafikmodus starten“. Diese einfachere Grafik läuft auf fast jedem PC.\n2. Klicke auf „Grafiktreiber aktualisieren“ und installiere den neuesten Treiber für deine {0}. Danach startet das Spiel meist auch wieder mit normaler Grafik.",
                Laptop = "3. Laptop mit zwei Grafikchips? Öffne in Windows Einstellungen → System → Bildschirm → Grafik, füge über „Durchsuchen“ die Datei GS_game.exe aus dem Spielordner hinzu und stelle sie auf „Hohe Leistung“.",
                SafeFailed = "Generation Ship wurde beim Starten beendet, auch im sicheren Grafikmodus.\n\nSo kannst du es beheben:\n1. Klicke auf „Grafiktreiber aktualisieren“, installiere den neuesten Treiber für deine {0} und starte den PC neu.\n2. Klicke in Steam mit der rechten Maustaste auf Generation Ship → Eigenschaften → Installierte Dateien → „Dateien auf Fehler überprüfen“.\n3. Klappt es immer noch nicht? Setze unten den Haken bei „Fehlerbericht senden“, dann sehen wir, was passiert ist. Schreib uns gern auch im Steam-Diskussionsforum von Generation Ship.",
                Closed = "Generation Ship wurde unerwartet beendet.\n\nSo kannst du es beheben:\n1. Klicke auf „Neu starten“.\n2. Passiert es wieder, aktualisiere den Treiber deiner {0} („Grafiktreiber aktualisieren“) oder starte im sicheren Grafikmodus.\n3. Setze unten den Haken bei „Fehlerbericht senden“. So können wir den Fehler finden und beheben.",
                DllMissing = "Generation Ship konnte nicht starten, weil eine Windows-Komponente oder Spieldatei fehlt.\n\nSo kannst du es beheben:\n1. Klicke in Steam mit der rechten Maustaste auf Generation Ship → Eigenschaften → Installierte Dateien → „Dateien auf Fehler überprüfen“.\n2. Klicke auf „Visual C++ herunterladen“, installiere das „x64“-Paket und starte den PC neu.",
                YourCard = "Grafikkarte",
                Safe = "Im sicheren Grafikmodus starten", Normal = "Mit normaler Grafik starten", Restart = "Neu starten",
                RestartSafe = "Im sicheren Grafikmodus neu starten", Driver = "Grafiktreiber aktualisieren", VcRedist = "Visual C++ herunterladen",
                Logs = "Log-Ordner öffnen", Close = "Schließen", Code = "Fehlercode",
                Send = "Fehlerbericht senden: an Happy Capy Games (Logdatei, Grafikkarte, Windows-Version, keine persönlichen Daten)",
                Missing = "GS_game.exe wurde nicht gefunden.\n\nSo kannst du es beheben: Klicke in Steam mit der rechten Maustaste auf Generation Ship → Eigenschaften → Installierte Dateien → „Dateien auf Fehler überprüfen“. Prüfe auch, ob dein Virenscanner die Datei in die Quarantäne verschoben hat.",
                SafeOnStart = "Generation Ship startet im sicheren Grafikmodus, weil das Spiel beim letzten Mal beim Starten beendet wurde.\n\nHast du seitdem deinen Grafiktreiber aktualisiert? Dann probiere die normale Grafik aus, sie sieht besser aus. Wird das Spiel wieder beendet, kannst du jederzeit zurück in den sicheren Grafikmodus wechseln.",
                KeepSafe = "Sicheren Grafikmodus behalten", TryNormal = "Normale Grafik ausprobieren", DontAsk = "Nicht mehr fragen",
            };
            case "es": return new Strings
            {
                StartFailed = "Generation Ship se cerró al iniciarse. Casi siempre se debe al controlador gráfico.\n\nCómo solucionarlo:\n1. Haz clic en «Iniciar en modo gráfico seguro». Estos gráficos más sencillos funcionan en casi cualquier PC.\n2. Haz clic en «Actualizar controlador gráfico» e instala el controlador más reciente para tu {0}. Después, el juego suele volver a funcionar con gráficos normales.",
                Laptop = "3. ¿Portátil con dos chips gráficos? En Windows, abre Configuración → Sistema → Pantalla → Gráficos, añade con «Examinar» el archivo GS_game.exe de la carpeta del juego y elige «Alto rendimiento».",
                SafeFailed = "Generation Ship se cerró al iniciarse, incluso en modo gráfico seguro.\n\nCómo solucionarlo:\n1. Haz clic en «Actualizar controlador gráfico», instala el controlador más reciente para tu {0} y reinicia el PC.\n2. En Steam, haz clic derecho en Generation Ship → Propiedades → Archivos instalados → «Verificar integridad de los archivos del juego».\n3. ¿Sigue sin funcionar? Marca abajo «Enviar un informe de error» para que veamos qué pasó, y escríbenos en las discusiones de Generation Ship en Steam.",
                Closed = "Generation Ship se cerró inesperadamente.\n\nCómo solucionarlo:\n1. Haz clic en «Reiniciar».\n2. Si vuelve a pasar, actualiza el controlador de tu {0} («Actualizar controlador gráfico») o reinicia en modo gráfico seguro.\n3. Marca abajo «Enviar un informe de error». Nos ayuda a encontrar y corregir el fallo.",
                DllMissing = "Generation Ship no pudo iniciarse porque falta un componente de Windows o un archivo del juego.\n\nCómo solucionarlo:\n1. En Steam, haz clic derecho en Generation Ship → Propiedades → Archivos instalados → «Verificar integridad de los archivos del juego».\n2. Haz clic en «Descargar Visual C++», instala el paquete «x64» y reinicia el PC.",
                YourCard = "tarjeta gráfica",
                Safe = "Iniciar en modo gráfico seguro", Normal = "Iniciar con gráficos normales", Restart = "Reiniciar",
                RestartSafe = "Reiniciar en modo gráfico seguro", Driver = "Actualizar controlador gráfico", VcRedist = "Descargar Visual C++",
                Logs = "Abrir carpeta de registros", Close = "Cerrar", Code = "Código de error",
                Send = "Enviar un informe de error a Happy Capy Games (archivo de registro, tarjeta gráfica, versión de Windows; sin datos personales)",
                Missing = "No se encontró GS_game.exe.\n\nCómo solucionarlo: en Steam, haz clic derecho en Generation Ship → Propiedades → Archivos instalados → «Verificar integridad de los archivos del juego». Comprueba también si tu antivirus ha puesto el archivo en cuarentena.",
                SafeOnStart = "Generation Ship se iniciará en modo gráfico seguro porque la última vez se cerró al iniciarse.\n\n¿Has actualizado el controlador gráfico desde entonces? Entonces prueba los gráficos normales: se ven mejor. Si el juego vuelve a cerrarse, podrás volver al modo gráfico seguro en cualquier momento.",
                KeepSafe = "Mantener modo gráfico seguro", TryNormal = "Probar gráficos normales", DontAsk = "No volver a preguntar",
            };
            case "fr": return new Strings
            {
                StartFailed = "Generation Ship s'est arrêté au démarrage. C'est presque toujours dû au pilote graphique.\n\nPour régler le problème :\n1. Cliquez sur « Démarrer en mode graphique sans échec ». Ces graphismes plus simples fonctionnent sur presque tous les PC.\n2. Cliquez sur « Mettre à jour le pilote graphique » et installez le dernier pilote pour votre {0}. Ensuite, le jeu fonctionne généralement de nouveau avec les graphismes normaux.",
                Laptop = "3. Portable avec deux puces graphiques ? Dans Windows, ouvrez Paramètres → Système → Écran → Graphiques, ajoutez via « Parcourir » le fichier GS_game.exe du dossier du jeu et choisissez « Performances élevées ».",
                SafeFailed = "Generation Ship s'est arrêté au démarrage, même en mode graphique sans échec.\n\nPour régler le problème :\n1. Cliquez sur « Mettre à jour le pilote graphique », installez le dernier pilote pour votre {0} et redémarrez le PC.\n2. Dans Steam, faites un clic droit sur Generation Ship → Propriétés → Fichiers installés → « Vérifier l'intégrité des fichiers du jeu ».\n3. Toujours bloqué ? Cochez « Envoyer un rapport d'erreur » ci-dessous pour que nous puissions voir ce qui s'est passé, et écrivez-nous dans les discussions Steam de Generation Ship.",
                Closed = "Generation Ship s'est fermé de manière inattendue.\n\nPour régler le problème :\n1. Cliquez sur « Redémarrer ».\n2. Si cela se reproduit, mettez à jour le pilote de votre {0} (« Mettre à jour le pilote graphique ») ou redémarrez en mode graphique sans échec.\n3. Cochez « Envoyer un rapport d'erreur » ci-dessous. Cela nous aide à trouver et corriger le problème.",
                DllMissing = "Generation Ship n'a pas pu démarrer : un composant de Windows ou un fichier du jeu est manquant.\n\nPour régler le problème :\n1. Dans Steam, faites un clic droit sur Generation Ship → Propriétés → Fichiers installés → « Vérifier l'intégrité des fichiers du jeu ».\n2. Cliquez sur « Télécharger Visual C++ », installez le paquet « x64 » et redémarrez le PC.",
                YourCard = "carte graphique",
                Safe = "Démarrer en mode graphique sans échec", Normal = "Démarrer avec les graphismes normaux", Restart = "Redémarrer",
                RestartSafe = "Redémarrer en mode graphique sans échec", Driver = "Mettre à jour le pilote graphique", VcRedist = "Télécharger Visual C++",
                Logs = "Ouvrir le dossier des journaux", Close = "Fermer", Code = "Code d'erreur",
                Send = "Envoyer un rapport d'erreur à Happy Capy Games (fichier journal, carte graphique, version de Windows ; aucune donnée personnelle)",
                Missing = "GS_game.exe est introuvable.\n\nPour régler le problème : dans Steam, faites un clic droit sur Generation Ship → Propriétés → Fichiers installés → « Vérifier l'intégrité des fichiers du jeu ». Vérifiez aussi que votre antivirus n'a pas mis le fichier en quarantaine.",
                SafeOnStart = "Generation Ship démarre en mode graphique sans échec, car le jeu s'est arrêté au démarrage la dernière fois.\n\nVous avez mis à jour votre pilote graphique depuis ? Essayez alors les graphismes normaux : ils sont plus beaux. Si le jeu se ferme à nouveau, vous pourrez toujours revenir au mode graphique sans échec.",
                KeepSafe = "Garder le mode sans échec", TryNormal = "Essayer les graphismes normaux", DontAsk = "Ne plus demander",
            };
            case "it": return new Strings
            {
                StartFailed = "Generation Ship si è chiuso durante l'avvio. Quasi sempre la causa è il driver grafico.\n\nCome risolvere:\n1. Fai clic su «Avvia in modalità grafica sicura». Questa grafica più semplice funziona su quasi tutti i PC.\n2. Fai clic su «Aggiorna driver grafico» e installa il driver più recente per la tua {0}. Dopo, di solito il gioco funziona di nuovo anche con la grafica normale.",
                Laptop = "3. Portatile con due chip grafici? In Windows apri Impostazioni → Sistema → Schermo → Grafica, aggiungi con «Sfoglia» il file GS_game.exe dalla cartella del gioco e scegli «Prestazioni elevate».",
                SafeFailed = "Generation Ship si è chiuso durante l'avvio, anche in modalità grafica sicura.\n\nCome risolvere:\n1. Fai clic su «Aggiorna driver grafico», installa il driver più recente per la tua {0} e riavvia il PC.\n2. In Steam, fai clic destro su Generation Ship → Proprietà → File installati → «Verifica l'integrità dei file di gioco».\n3. Ancora niente? Spunta qui sotto «Invia una segnalazione di errore» così vediamo cosa è successo, e scrivici nelle discussioni di Generation Ship su Steam.",
                Closed = "Generation Ship si è chiuso in modo imprevisto.\n\nCome risolvere:\n1. Fai clic su «Riavvia».\n2. Se succede di nuovo, aggiorna il driver della tua {0} («Aggiorna driver grafico») o riavvia in modalità grafica sicura.\n3. Spunta qui sotto «Invia una segnalazione di errore». Ci aiuta a trovare e correggere il problema.",
                DllMissing = "Generation Ship non è riuscito ad avviarsi perché manca un componente di Windows o un file del gioco.\n\nCome risolvere:\n1. In Steam, fai clic destro su Generation Ship → Proprietà → File installati → «Verifica l'integrità dei file di gioco».\n2. Fai clic su «Scarica Visual C++», installa il pacchetto «x64» e riavvia il PC.",
                YourCard = "scheda grafica",
                Safe = "Avvia in modalità grafica sicura", Normal = "Avvia con grafica normale", Restart = "Riavvia",
                RestartSafe = "Riavvia in modalità grafica sicura", Driver = "Aggiorna driver grafico", VcRedist = "Scarica Visual C++",
                Logs = "Apri la cartella dei log", Close = "Chiudi", Code = "Codice di errore",
                Send = "Invia una segnalazione di errore a Happy Capy Games (file di log, scheda grafica, versione di Windows; nessun dato personale)",
                Missing = "GS_game.exe non trovato.\n\nCome risolvere: in Steam, fai clic destro su Generation Ship → Proprietà → File installati → «Verifica l'integrità dei file di gioco». Controlla anche che l'antivirus non abbia messo il file in quarantena.",
                SafeOnStart = "Generation Ship si avvia in modalità grafica sicura perché l'ultima volta si è chiuso durante l'avvio.\n\nHai aggiornato il driver grafico nel frattempo? Allora prova la grafica normale: è più bella. Se il gioco si chiude di nuovo, potrai sempre tornare alla modalità grafica sicura.",
                KeepSafe = "Mantieni la modalità sicura", TryNormal = "Prova la grafica normale", DontAsk = "Non chiedere più",
            };
            case "pl": return new Strings
            {
                StartFailed = "Generation Ship zamknęło się podczas uruchamiania. Prawie zawsze przyczyną jest sterownik karty graficznej.\n\nJak to naprawić:\n1. Kliknij „Uruchom w bezpiecznym trybie graficznym”. Ta prostsza grafika działa niemal na każdym komputerze.\n2. Kliknij „Zaktualizuj sterownik grafiki” i zainstaluj najnowszy sterownik dla karty {0}. Potem gra zwykle znów działa także z normalną grafiką.",
                Laptop = "3. Laptop z dwoma układami graficznymi? W Windows otwórz Ustawienia → System → Ekran → Grafika, dodaj przez „Przeglądaj” plik GS_game.exe z folderu gry i wybierz „Wysoka wydajność”.",
                SafeFailed = "Generation Ship zamknęło się podczas uruchamiania, również w bezpiecznym trybie graficznym.\n\nJak to naprawić:\n1. Kliknij „Zaktualizuj sterownik grafiki”, zainstaluj najnowszy sterownik dla karty {0} i uruchom komputer ponownie.\n2. W Steam kliknij prawym przyciskiem Generation Ship → Właściwości → Zainstalowane pliki → „Zweryfikuj spójność plików gry”.\n3. Nadal nie działa? Zaznacz poniżej „Wyślij raport o błędzie”, żebyśmy zobaczyli, co się stało, i napisz do nas w dyskusjach Generation Ship na Steam.",
                Closed = "Generation Ship nieoczekiwanie się zamknęło.\n\nJak to naprawić:\n1. Kliknij „Uruchom ponownie”.\n2. Jeśli to się powtórzy, zaktualizuj sterownik karty {0} („Zaktualizuj sterownik grafiki”) lub uruchom grę w bezpiecznym trybie graficznym.\n3. Zaznacz poniżej „Wyślij raport o błędzie”. Pomoże nam to znaleźć i naprawić problem.",
                DllMissing = "Nie udało się uruchomić Generation Ship, ponieważ brakuje składnika Windows lub pliku gry.\n\nJak to naprawić:\n1. W Steam kliknij prawym przyciskiem Generation Ship → Właściwości → Zainstalowane pliki → „Zweryfikuj spójność plików gry”.\n2. Kliknij „Pobierz Visual C++”, zainstaluj pakiet „x64” i uruchom komputer ponownie.",
                YourCard = "graficznej",
                Safe = "Uruchom w bezpiecznym trybie graficznym", Normal = "Uruchom z normalną grafiką", Restart = "Uruchom ponownie",
                RestartSafe = "Uruchom ponownie w trybie bezpiecznym", Driver = "Zaktualizuj sterownik grafiki", VcRedist = "Pobierz Visual C++",
                Logs = "Otwórz folder dzienników", Close = "Zamknij", Code = "Kod błędu",
                Send = "Wyślij raport o błędzie do Happy Capy Games (plik dziennika, karta graficzna, wersja Windows; bez danych osobowych)",
                Missing = "Nie znaleziono GS_game.exe.\n\nJak to naprawić: w Steam kliknij prawym przyciskiem Generation Ship → Właściwości → Zainstalowane pliki → „Zweryfikuj spójność plików gry”. Sprawdź też, czy program antywirusowy nie przeniósł pliku do kwarantanny.",
                SafeOnStart = "Generation Ship uruchomi się w bezpiecznym trybie graficznym, ponieważ ostatnio gra zamknęła się podczas uruchamiania.\n\nCzy od tego czasu sterownik grafiki został zaktualizowany? Wypróbuj wtedy normalną grafikę – wygląda lepiej. Jeśli gra znów się zamknie, zawsze możesz wrócić do bezpiecznego trybu graficznego.",
                KeepSafe = "Zostaw tryb bezpieczny", TryNormal = "Wypróbuj normalną grafikę", DontAsk = "Nie pytaj ponownie",
            };
            default: return new Strings
            {
                StartFailed = "Generation Ship closed while starting. This is almost always caused by the graphics driver.\n\nHow to fix it:\n1. Click \"Start in safe graphics mode\". These simpler graphics work on almost every PC.\n2. Click \"Update graphics driver\" and install the newest driver for your {0}. After that the game usually runs with normal graphics again.",
                Laptop = "3. Laptop with two graphics chips? In Windows, open Settings → System → Display → Graphics, add GS_game.exe from the game folder with \"Browse\" and set it to \"High performance\".",
                SafeFailed = "Generation Ship closed while starting, even in safe graphics mode.\n\nHow to fix it:\n1. Click \"Update graphics driver\", install the newest driver for your {0} and restart your PC.\n2. In Steam, right-click Generation Ship → Properties → Installed Files → \"Verify integrity of game files\".\n3. Still not working? Tick \"Send an error report\" below so we can see what happened, and tell us in the Generation Ship discussions on Steam.",
                Closed = "Generation Ship closed unexpectedly.\n\nHow to fix it:\n1. Click \"Restart\".\n2. If it happens again, update the driver for your {0} (\"Update graphics driver\") or restart in safe graphics mode.\n3. Tick \"Send an error report\" below. It helps us find and fix the problem.",
                DllMissing = "Generation Ship couldn't start because a Windows component or a game file is missing.\n\nHow to fix it:\n1. In Steam, right-click Generation Ship → Properties → Installed Files → \"Verify integrity of game files\".\n2. Click \"Get Visual C++\", install the \"x64\" package and restart your PC.",
                YourCard = "graphics card",
                Safe = "Start in safe graphics mode", Normal = "Start with normal graphics", Restart = "Restart",
                RestartSafe = "Restart in safe graphics mode", Driver = "Update graphics driver", VcRedist = "Get Visual C++",
                Logs = "Open log folder", Close = "Close", Code = "Error code",
                Send = "Send an error report to Happy Capy Games (log file, graphics card, Windows version; no personal data)",
                Missing = "GS_game.exe was not found.\n\nHow to fix it: in Steam, right-click Generation Ship → Properties → Installed Files → \"Verify integrity of game files\". Also check whether your antivirus moved the file to quarantine.",
                SafeOnStart = "Generation Ship is starting in safe graphics mode, because it closed while starting last time.\n\nHave you updated your graphics driver since then? Then try normal graphics: they look better. If the game closes again, you can always switch back to safe graphics mode.",
                KeepSafe = "Keep safe graphics", TryNormal = "Try normal graphics", DontAsk = "Don't ask again",
            };
        }
    }
}
