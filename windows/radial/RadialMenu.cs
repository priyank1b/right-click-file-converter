// Radial Convert - a hotkey-activated radial (pie) menu for converting the selected files.
// Press the hotkey with file(s) selected in File Explorer (or on the Desktop); a ring of
// output formats appears at the mouse pointer. Hover to highlight, click to convert.
//
// Built with the .NET Framework C# compiler that ships with Windows (C# 5): no extra installs.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using Ellipse = System.Windows.Shapes.Ellipse;
using WPath = System.Windows.Shapes.Path;
using System.Windows.Threading;

namespace RadialConvert
{
    // ------------------------------------------------------------------ routing (mirrors Convert.ps1)
    static class Routing
    {
        static readonly string[] Image = { "jpg", "jpeg", "jfif", "png", "webp", "bmp", "gif", "tif", "tiff", "heic", "heif", "avif", "ico" };
        static readonly string[] Video = { "mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v", "mpg", "mpeg", "3gp", "ts", "mts", "m2ts", "vob" };
        static readonly string[] Audio = { "mp3", "wav", "flac", "aac", "m4a", "ogg", "opus", "wma", "aiff", "aif" };
        static readonly string[] Doc = { "doc", "docx", "odt", "rtf", "txt", "wpd" };
        static readonly string[] Sheet = { "xls", "xlsx", "ods", "csv" };
        static readonly string[] Slides = { "ppt", "pptx", "odp" };

        public static string KindFor(string ext)
        {
            ext = ext.ToLowerInvariant();
            if (Image.Contains(ext)) return "image";
            if (Video.Contains(ext)) return "video";
            if (Audio.Contains(ext)) return "audio";
            if (Doc.Contains(ext)) return "doc";
            if (Sheet.Contains(ext)) return "sheet";
            if (Slides.Contains(ext)) return "slides";
            if (ext == "md" || ext == "markdown") return "md";
            if (ext == "html" || ext == "htm") return "html";
            if (ext == "epub") return "epub";
            if (ext == "pdf") return "pdf";
            if (ext == "ai") return "ai";
            return null;
        }

        public static string[] TargetsFor(string kind)
        {
            switch (kind)
            {
                case "image": return new[] { "png", "jpg", "webp", "bmp", "gif", "tiff", "ico", "pdf", "resize" };
                case "video": return new[] { "mp4", "mkv", "avi", "mov", "webm", "gif", "mp3", "wav", "m4a", "flac" };
                case "audio": return new[] { "mp3", "wav", "flac", "aac", "m4a", "ogg", "opus" };
                case "doc": return new[] { "pdf", "docx", "odt", "rtf", "txt", "html" };
                case "sheet": return new[] { "pdf", "xlsx", "ods", "csv", "html" };
                case "slides": return new[] { "pdf", "pptx", "odp" };
                case "md": return new[] { "docx", "html", "txt", "epub", "pdf" };
                case "html": return new[] { "docx", "md", "txt", "epub", "pdf" };
                case "epub": return new[] { "docx", "html", "md", "txt" };
                case "pdf": return new[] { "png", "jpg", "docx", "odt", "txt" };
                case "ai": return new[] { "cdr", "svg", "pdf", "eps", "png", "jpg" };
            }
            return new string[0];
        }

        static string[] Needs(string kind, string target)
        {
            switch (kind)
            {
                case "image": return new[] { "magick" };
                case "video": case "audio": return new[] { "ffmpeg" };
                case "doc": case "sheet": case "slides": return new[] { "soffice" };
                case "md": return target == "pdf" ? new[] { "pandoc", "soffice" } : new[] { "pandoc" };
                case "html": return target == "pdf" ? new[] { "soffice" } : new[] { "pandoc" };
                case "epub": return new[] { "pandoc" };
                case "pdf": return (target == "png" || target == "jpg") ? new[] { "magick" } : new[] { "soffice" };
                case "ai":
                    if (target == "cdr") return new[] { "corel" };
                    if (target == "svg") return new[] { "gs", "svgpy" };
                    return new[] { "gs" };
            }
            return new string[0];
        }

        public static string Normalize(string ext)
        {
            ext = ext.ToLowerInvariant();
            switch (ext)
            {
                case "jpeg": case "jfif": return "jpg";
                case "tif": return "tiff";
                case "htm": return "html";
                case "markdown": return "md";
                case "aif": return "aiff";
                case "heif": return "heic";
            }
            return ext;
        }

        // Formats to offer for a file of this extension, honouring which tools are installed.
        public static List<string> Offer(string ext)
        {
            string kind = KindFor(ext);
            var list = new List<string>();
            if (kind == null) return list;
            string norm = Normalize(ext);
            foreach (string t in TargetsFor(kind))
            {
                if (t == norm) continue;
                bool ok = true;
                foreach (string n in Needs(kind, t)) { if (!Tools.Has(n)) { ok = false; break; } }
                if (ok) list.Add(t);
            }
            return list;
        }

        public static string PluralName(string kind)
        {
            switch (kind)
            {
                case "image": return "images";
                case "video": return "videos";
                case "audio": return "audio files";
                case "doc": return "documents";
                case "sheet": return "spreadsheets";
                case "slides": return "presentations";
                case "md": return "Markdown files";
                case "html": return "HTML files";
                case "epub": return "EPUB files";
                case "pdf": return "PDFs";
                case "ai": return "Illustrator files";
            }
            return "unsupported files";
        }

        public static string Sub(string kind, string target)
        {
            if (kind == "video" && (target == "mp3" || target == "wav" || target == "m4a" || target == "flac")) return "audio only";
            if (kind == "video" && target == "gif") return "animated";
            if (kind == "pdf" && (target == "png" || target == "jpg")) return "per page";
            if (kind == "pdf" && (target == "docx" || target == "odt" || target == "txt")) return "approx.";
            if (kind == "image" && target == "resize") return "px or KB";
            if (kind == "ai" && target == "cdr") return "CorelDRAW";
            if (kind == "ai" && target != "pdf") return "per artboard";
            return "";
        }
    }

    // ------------------------------------------------------------------ which converters are installed
    static class Tools
    {
        static Dictionary<string, bool> cache = new Dictionary<string, bool>();
        static DateTime stamp = DateTime.MinValue;

        static string[] Dirs()
        {
            var dirs = new List<string>();
            string machine = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.Machine) ?? "";
            string user = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? "";
            foreach (string p in (machine + ";" + user).Split(';')) if (p.Trim().Length > 0) dirs.Add(Environment.ExpandEnvironmentVariables(p.Trim()));
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            string pf86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            dirs.Add(Path.Combine(local, @"Microsoft\WinGet\Links"));
            dirs.Add(Path.Combine(local, "Pandoc"));
            dirs.Add(Path.Combine(pf, "Pandoc"));
            dirs.Add(Path.Combine(pf, @"LibreOffice\program"));
            dirs.Add(Path.Combine(pf86, @"LibreOffice\program"));
            dirs.AddRange(Glob(Path.Combine(local, @"Microsoft\WinGet\Packages"), "Gyan.FFmpeg*", "ffmpeg-*", "bin"));
            dirs.AddRange(Glob(pf, "ImageMagick*"));
            return dirs.ToArray();
        }

        // Expand "<root>\<pattern1>\<pattern2>..." style folder globs.
        static List<string> Glob(string root, params string[] patterns)
        {
            var current = new List<string>();
            if (Directory.Exists(root)) current.Add(root);
            foreach (string pat in patterns)
            {
                var next = new List<string>();
                foreach (string c in current)
                {
                    try { next.AddRange(Directory.GetDirectories(c, pat)); } catch { }
                }
                current = next;
            }
            return current;
        }

        public static bool Has(string tool)
        {
            if (DateTime.UtcNow - stamp > TimeSpan.FromSeconds(60)) { cache.Clear(); stamp = DateTime.UtcNow; }
            bool v;
            if (cache.TryGetValue(tool, out v)) return v;
            v = false;
            string appDir = Path.GetDirectoryName(typeof(Tools).Assembly.Location);
            if (tool == "corel")
            {
                // only CorelDRAW itself can write .cdr; it registers this automation class
                try { using (var k = Microsoft.Win32.Registry.ClassesRoot.OpenSubKey(@"CorelDRAW.Application\CLSID")) v = k != null; } catch { }
                v = v && File.Exists(Path.Combine(appDir, "ai2cdr.ps1"));
                cache[tool] = v;
                return v;
            }
            if (tool == "svgpy")
            {
                // python alone isn't enough: PyMuPDF must have installed into the environment
                v = File.Exists(Path.Combine(appDir, @"pyenv\Scripts\python.exe")) && File.Exists(Path.Combine(appDir, "ai_svg_run.py"))
                    && Directory.Exists(Path.Combine(appDir, @"pyenv\Lib\site-packages\pymupdf"));
                cache[tool] = v;
                return v;
            }
            if (tool == "gs")
            {
                string pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
                foreach (string d in Glob(Path.Combine(pf, "gs"), "gs*", "bin"))
                    if (File.Exists(Path.Combine(d, "gswin64c.exe"))) { v = true; break; }
                if (v) { cache[tool] = v; return v; }
            }
            string[] names = tool == "soffice" ? new[] { "soffice.com", "soffice.exe" } : tool == "gs" ? new[] { "gswin64c.exe" } : new[] { tool + ".exe" };
            foreach (string d in Dirs())
            {
                foreach (string n in names)
                {
                    try { if (File.Exists(Path.Combine(d, n))) { v = true; break; } } catch { }
                }
                if (v) break;
            }
            cache[tool] = v;
            return v;
        }
    }

    // ------------------------------------------------------------------ files selected in Explorer / Desktop
    static class Selection
    {
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder sb, int max);

        public static List<string> Get()
        {
            var result = new List<string>();
            try
            {
                IntPtr fg = GetForegroundWindow();
                dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("Shell.Application"));
                dynamic wins = shell.Windows();
                int n = wins.Count;
                for (int i = 0; i < n && result.Count == 0; i++)
                {
                    try
                    {
                        dynamic w = wins.Item(i);
                        if (w == null) continue;
                        if ((long)w.HWND != fg.ToInt64()) continue;
                        result = Read(w.Document.SelectedItems());
                    }
                    catch { }
                }
                if (result.Count == 0)
                {
                    var sb = new StringBuilder(64);
                    GetClassName(fg, sb, 64);
                    string cls = sb.ToString();
                    if (cls == "Progman" || cls == "WorkerW")
                    {
                        try
                        {
                            object loc = 0; object empty = null; int hw;
                            dynamic desk = wins.FindWindowSW(ref loc, ref empty, 8, out hw, 1);
                            result = Read(desk.Document.SelectedItems());
                        }
                        catch { }
                    }
                }
            }
            catch { }
            return result;
        }

        public static List<string> Diagnostics()
        {
            var d = new List<string>();
            try
            {
                IntPtr fg = GetForegroundWindow();
                var sb = new StringBuilder(64); GetClassName(fg, sb, 64);
                d.Add("foreground HWND=" + fg.ToInt64() + " class=" + sb);
                dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("Shell.Application"));
                dynamic wins = shell.Windows();
                int n = wins.Count;
                for (int i = 0; i < n; i++)
                {
                    try
                    {
                        dynamic w = wins.Item(i);
                        string sel = "?";
                        try { sel = ((int)w.Document.SelectedItems().Count).ToString(); } catch (Exception e) { sel = "err:" + e.Message; }
                        d.Add("window " + i + ": HWND=" + (long)w.HWND + " selected=" + sel + " url=" + w.LocationURL);
                    }
                    catch (Exception e) { d.Add("window " + i + ": error " + e.Message); }
                }
            }
            catch (Exception e) { d.Add("diagnostics failed: " + e.Message); }
            return d;
        }

        static List<string> Read(dynamic items)
        {
            var list = new List<string>();
            int c = items.Count;
            for (int j = 0; j < c; j++)
            {
                string p = (string)items.Item(j).Path;
                if (!string.IsNullOrEmpty(p) && File.Exists(p)) list.Add(p);
            }
            return list;
        }
    }

    // ------------------------------------------------------------------ the radial visual
    class RadialVisual : Canvas
    {
        public const double InnerR = 66, OuterR = 160, Pad = 34;
        public static readonly double Dim = 2 * (OuterR + Pad);

        readonly List<string> targets;
        readonly string kind;
        readonly string title;
        readonly List<Canvas> items = new List<Canvas>();
        readonly List<WPath> wedges = new List<WPath>();
        readonly List<TextBlock> labels = new List<TextBlock>();
        readonly List<TextBlock> subs = new List<TextBlock>();
        readonly List<TranslateTransform> shifts = new List<TranslateTransform>();
        TextBlock centerTop, centerMain, centerHint;
        int hover = -1;
        double step;

        // "frosted glass" palette: translucent white tiles over a blurred, tinted backdrop
        public const double GlassR = OuterR + 3;
        static readonly Brush WedgeFill = Frozen(Vertical(Color.FromArgb(0x30, 0xFF, 0xFF, 0xFF), Color.FromArgb(0x10, 0xFF, 0xFF, 0xFF)));
        static readonly Brush WedgeHover = Frozen(Vertical(Color.FromArgb(0xE6, 0x66, 0xB0, 0xFF), Color.FromArgb(0xE6, 0x1C, 0x6C, 0xF2)));
        static readonly Brush Stroke = Frozen(new SolidColorBrush(Color.FromArgb(0x50, 0xFF, 0xFF, 0xFF)));
        static readonly Brush StrokeHover = Frozen(new SolidColorBrush(Color.FromArgb(0xD8, 0xFF, 0xFF, 0xFF)));
        static readonly Brush TextNormal = Frozen(new SolidColorBrush(Color.FromArgb(0xF5, 0xFF, 0xFF, 0xFF)));
        static readonly Brush TextDim = Frozen(new SolidColorBrush(Color.FromArgb(0xB8, 0xFF, 0xFF, 0xFF)));
        static readonly Brush TextHoverDim = Frozen(new SolidColorBrush(Color.FromArgb(0xE6, 0xFF, 0xFF, 0xFF)));
        static readonly Effect TextShadow = MakeTextShadow();

        static Effect MakeTextShadow()
        {
            var e = new DropShadowEffect { Color = Colors.Black, BlurRadius = 5, ShadowDepth = 1, Opacity = 0.45 };
            e.Freeze();
            return e;
        }

        static LinearGradientBrush Vertical(Color top, Color bottom)
        {
            return new LinearGradientBrush(top, bottom, 90);
        }

        static Brush Frozen(Brush b) { b.Freeze(); return b; }

        readonly byte tint;

        // tint: alpha of the dark glass-tint disc drawn under the slices (lighter when a real blur sits behind it)
        readonly ImageSource behind;

        // behind: a screenshot of what is behind the ring (Dim x Dim); drawn blurred inside the glass disc
        public RadialVisual(List<string> targets, string kind, string title, byte tint = 0x99, ImageSource behind = null)
        {
            this.targets = targets;
            this.kind = kind;
            this.title = title;
            this.tint = tint;
            this.behind = behind;
            Width = Dim; Height = Dim;
            step = 360.0 / Math.Max(1, targets.Count);
            Build();
        }

        double C { get { return Dim / 2; } }

        Point Polar(double r, double deg)
        {
            double a = deg * Math.PI / 180.0;
            return new Point(C + r * Math.Cos(a), C + r * Math.Sin(a));
        }

        Geometry Sector(double r0, double r1, double a0, double a1)
        {
            bool big = (a1 - a0) > 180;
            var g = new StreamGeometry();
            using (StreamGeometryContext ctx = g.Open())
            {
                ctx.BeginFigure(Polar(r1, a0), true, true);
                ctx.ArcTo(Polar(r1, a1), new System.Windows.Size(r1, r1), 0, big, SweepDirection.Clockwise, true, false);
                ctx.LineTo(Polar(r0, a1), true, false);
                ctx.ArcTo(Polar(r0, a0), new System.Windows.Size(r0, r0), 0, big, SweepDirection.Counterclockwise, true, false);
            }
            g.Freeze();
            return g;
        }

        TextBlock Text(string s, double size, FontWeight weight, Brush brush)
        {
            return new TextBlock
            {
                Text = s,
                FontFamily = new FontFamily("Segoe UI"),
                FontSize = size,
                FontWeight = weight,
                Foreground = brush,
                TextAlignment = TextAlignment.Center,
                TextTrimming = TextTrimming.CharacterEllipsis
            };
        }

        void Build()
        {
            // soft shadow just outside the glass edge (stroke only, so it never darkens the glass itself)
            double sr = GlassR + 9;
            var shadow = new Ellipse { Width = 2 * sr, Height = 2 * sr, Stroke = new SolidColorBrush(Color.FromArgb(0x58, 0, 0, 0)), StrokeThickness = 12, IsHitTestVisible = false };
            shadow.Effect = new BlurEffect { Radius = 10 };
            SetLeft(shadow, C - sr); SetTop(shadow, C - sr);
            Children.Add(shadow);

            if (behind != null)
            {
                // the blur lives on the image; the clip lives on the holder, so the blurred pixels are cut to a circle
                var holder = new Canvas { Width = Dim, Height = Dim, IsHitTestVisible = false, Clip = new EllipseGeometry(new Point(C, C), GlassR, GlassR) };
                var img = new System.Windows.Controls.Image
                {
                    Source = behind, Width = Dim, Height = Dim, Stretch = Stretch.Fill,
                    Effect = new BlurEffect { Radius = 26, KernelType = KernelType.Gaussian, RenderingBias = RenderingBias.Performance }
                };
                holder.Children.Add(img);
                Children.Add(holder);
            }

            if (tint > 0)
            {
                var disc0 = new Ellipse
                {
                    Width = 2 * GlassR, Height = 2 * GlassR, IsHitTestVisible = false,
                    Fill = new SolidColorBrush(Color.FromArgb(tint, 0x1C, 0x20, 0x2C))
                };
                SetLeft(disc0, C - GlassR); SetTop(disc0, C - GlassR);
                Children.Add(disc0);
            }

            double gap = targets.Count > 1 ? 2.2 : 0;
            for (int i = 0; i < targets.Count; i++)
            {
                double center = -90 + i * step;
                var item = new Canvas { Width = Dim, Height = Dim };
                var shift = new TranslateTransform();
                item.RenderTransform = shift;

                var wedge = new WPath
                {
                    Data = Sector(InnerR, OuterR, center - step / 2 + gap / 2, center + step / 2 - gap / 2),
                    Fill = WedgeFill,
                    Stroke = Stroke,
                    StrokeThickness = 1
                };
                item.Children.Add(wedge);

                string sub = Routing.Sub(kind, targets[i]);
                var panel = new StackPanel { Width = 74, Orientation = Orientation.Vertical, IsHitTestVisible = false };
                var lab = Text(targets[i].ToUpperInvariant(), 15, FontWeights.SemiBold, TextNormal);
                var sb = Text(sub, 9.5, FontWeights.Normal, TextDim);
                lab.Effect = TextShadow; sb.Effect = TextShadow;
                panel.Children.Add(lab);
                if (sub.Length > 0) panel.Children.Add(sb);
                Point mid = Polar((InnerR + OuterR) / 2, center);
                panel.Measure(new System.Windows.Size(74, 60));
                SetLeft(panel, mid.X - 37);
                SetTop(panel, mid.Y - panel.DesiredSize.Height / 2);
                item.Children.Add(panel);

                Children.Add(item);
                items.Add(item); wedges.Add(wedge); labels.Add(lab); subs.Add(sb); shifts.Add(shift);
            }

            // centre disc
            double cr = InnerR - 9;
            var disc = new Ellipse
            {
                Width = 2 * cr, Height = 2 * cr,
                Fill = new RadialGradientBrush(Color.FromArgb(0x4A, 0xFF, 0xFF, 0xFF), Color.FromArgb(0x1C, 0xFF, 0xFF, 0xFF)),
                Stroke = Stroke, StrokeThickness = 1, IsHitTestVisible = false
            };
            SetLeft(disc, C - cr); SetTop(disc, C - cr);
            Children.Add(disc);

            var cp = new StackPanel { Width = 2 * cr - 14, IsHitTestVisible = false };
            centerTop = Text(title, 10.5, FontWeights.Normal, TextDim);
            centerMain = Text("Convert to", 13, FontWeights.SemiBold, TextNormal);
            centerHint = Text("Esc to cancel", 9, FontWeights.Normal, TextDim);
            centerTop.Margin = new Thickness(0, 0, 0, 3);
            centerHint.Margin = new Thickness(0, 4, 0, 0);
            cp.Children.Add(centerTop); cp.Children.Add(centerMain); cp.Children.Add(centerHint);
            cp.Measure(new System.Windows.Size(cp.Width, 100));
            SetLeft(cp, C - cp.Width / 2);
            SetTop(cp, C - cp.DesiredSize.Height / 2);
            centerTop.Effect = TextShadow; centerMain.Effect = TextShadow; centerHint.Effect = TextShadow;
            Children.Add(cp);

            // glossy highlight across the top of the glass, clipped to the disc
            double gw = 2 * GlassR * 0.9, gh = GlassR * 0.95;
            double gl = C - gw / 2, gt = C - GlassR + 3;
            var gloss = new Ellipse
            {
                Width = gw, Height = gh, IsHitTestVisible = false,
                Fill = new RadialGradientBrush
                {
                    Center = new Point(0.5, 0.0), GradientOrigin = new Point(0.5, 0.0), RadiusX = 0.5, RadiusY = 0.95,
                    GradientStops = new GradientStopCollection {
                        new GradientStop(Color.FromArgb(0x52, 0xFF, 0xFF, 0xFF), 0.0),
                        new GradientStop(Color.FromArgb(0x00, 0xFF, 0xFF, 0xFF), 1.0) }
                },
                Clip = new EllipseGeometry(new Point(C - gl, C - gt), GlassR - 3, GlassR - 3)
            };
            SetLeft(gloss, gl); SetTop(gloss, gt);
            Children.Add(gloss);

            // light rim: bright outer edge + faint inner edge, like the edge of a glass pane
            var rim = new Ellipse { Width = 2 * GlassR, Height = 2 * GlassR, IsHitTestVisible = false, StrokeThickness = 1.4,
                Stroke = new LinearGradientBrush(Color.FromArgb(0xB0, 0xFF, 0xFF, 0xFF), Color.FromArgb(0x30, 0xFF, 0xFF, 0xFF), 90) };
            SetLeft(rim, C - GlassR); SetTop(rim, C - GlassR);
            Children.Add(rim);
            var rim2 = new Ellipse { Width = 2 * (GlassR - 2.5), Height = 2 * (GlassR - 2.5), IsHitTestVisible = false, StrokeThickness = 1,
                Stroke = new SolidColorBrush(Color.FromArgb(0x1C, 0xFF, 0xFF, 0xFF)) };
            SetLeft(rim2, C - GlassR + 2.5); SetTop(rim2, C - GlassR + 2.5);
            Children.Add(rim2);
        }

        public int Count { get { return targets.Count; } }
        public string TargetAt(int i) { return targets[i]; }

        // Which wedge is under this point (relative to this canvas)? -1 for none.
        public int HitIndex(Point p)
        {
            double dx = p.X - C, dy = p.Y - C;
            double r = Math.Sqrt(dx * dx + dy * dy);
            if (r < InnerR - 9 + 2 || r > OuterR + 26) return -1;
            double ang = Math.Atan2(dy, dx) * 180 / Math.PI;
            double rel = (ang + 90 + step / 2 + 720) % 360;
            int idx = (int)Math.Floor(rel / step);
            if (idx >= targets.Count) idx = targets.Count - 1;
            return idx;
        }

        public void SetHover(int idx)
        {
            if (idx == hover) return;
            if (hover >= 0) Apply(hover, false);
            hover = idx;
            if (hover >= 0) Apply(hover, true);
            centerMain.Text = hover >= 0 ? targets[hover].ToUpperInvariant() : "Convert to";
            centerMain.FontSize = hover >= 0 ? 19 : 13;
            centerMain.Foreground = hover >= 0 ? (Brush)Brushes.White : TextNormal;
            centerHint.Text = hover >= 0 ? "Click to convert" : "Esc to cancel";
        }

        void Apply(int i, bool on)
        {
            WPath w = wedges[i];
            w.Fill = on ? WedgeHover : WedgeFill;
            w.Stroke = on ? StrokeHover : Stroke;
            labels[i].Foreground = on ? (Brush)Brushes.White : TextNormal;
            subs[i].Foreground = on ? TextHoverDim : TextDim;
            labels[i].FontSize = on ? 17 : 15;

            // pop outward along the wedge's bisector
            double center = -90 + i * step;
            double a = center * Math.PI / 180.0;
            double d = on ? 7 : 0;
            Animate(shifts[i], TranslateTransform.XProperty, d * Math.Cos(a));
            Animate(shifts[i], TranslateTransform.YProperty, d * Math.Sin(a));
            items[i].Effect = on ? new DropShadowEffect { Color = Color.FromRgb(0x3B, 0x82, 0xF6), BlurRadius = 20, ShadowDepth = 0, Opacity = 0.85 } : null;
            if (on) Canvas.SetZIndex(items[i], 10); else Canvas.SetZIndex(items[i], 0);
        }

        static void Animate(TranslateTransform t, DependencyProperty p, double to)
        {
            t.BeginAnimation(p, new DoubleAnimation(to, TimeSpan.FromMilliseconds(90)) { EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut } });
        }
    }

    // ------------------------------------------------------------------ the full-screen overlay hosting the visual
    class RadialWindow : Window
    {
        [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
        [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }

        readonly RadialVisual visual;
        readonly Canvas root = new Canvas();
        readonly Stopwatch shown = Stopwatch.StartNew();
        public string Chosen;

        public void Present() { Show(); }

        [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);

        // Grab the screen pixels behind the ring (before our windows appear) so the glass can blur them.
        static ImageSource CaptureBackdrop(HwndSource src, double cxDip, double cyDip)
        {
            try
            {
                Matrix toDev = src.CompositionTarget.TransformToDevice;
                int pw = (int)Math.Round(RadialVisual.Dim * toDev.M11), ph = (int)Math.Round(RadialVisual.Dim * toDev.M22);
                Point c = toDev.Transform(new Point(cxDip, cyDip));
                int x = (int)Math.Round(c.X - pw / 2.0), y = (int)Math.Round(c.Y - ph / 2.0);
                using (var bmp = new System.Drawing.Bitmap(pw, ph, System.Drawing.Imaging.PixelFormat.Format32bppArgb))
                {
                    using (var g = System.Drawing.Graphics.FromImage(bmp))
                        g.CopyFromScreen(x, y, 0, 0, new System.Drawing.Size(pw, ph));
                    IntPtr hb = bmp.GetHbitmap();
                    try
                    {
                        BitmapSource bs = Imaging.CreateBitmapSourceFromHBitmap(hb, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                        bs.Freeze();
                        return bs;
                    }
                    finally { DeleteObject(hb); }
                }
            }
            catch { return null; }
        }

        public RadialWindow(List<string> targets, string kind, string title)
        {
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            Topmost = true;
            Background = new SolidColorBrush(Color.FromArgb(0x01, 0x00, 0x00, 0x00));   // practically invisible, but catches clicks
            Left = SystemParameters.VirtualScreenLeft;
            Top = SystemParameters.VirtualScreenTop;
            Width = SystemParameters.VirtualScreenWidth;
            Height = SystemParameters.VirtualScreenHeight;
            Content = root;

            // place the ring at the mouse pointer, kept on screen
            IntPtr hwnd = new WindowInteropHelper(this).EnsureHandle();
            POINT cp; GetCursorPos(out cp);
            HwndSource src = HwndSource.FromHwnd(hwnd);
            Point dip = src.CompositionTarget.TransformFromDevice.Transform(new Point(cp.X, cp.Y));
            double half = RadialVisual.Dim / 2 - 10;
            double cx = Math.Max(SystemParameters.VirtualScreenLeft + half, Math.Min(SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth - half, dip.X));
            double cy = Math.Max(SystemParameters.VirtualScreenTop + half, Math.Min(SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight - half, dip.Y));
            // frosted glass: the pixels behind the ring, blurred and tinted (plain dark tint if the grab fails)
            ImageSource behind = CaptureBackdrop(src, cx, cy);
            visual = new RadialVisual(targets, kind, title, behind != null ? (byte)0x58 : (byte)0x99, behind);
            root.Children.Add(visual);
            Canvas.SetLeft(visual, cx - SystemParameters.VirtualScreenLeft - RadialVisual.Dim / 2);
            Canvas.SetTop(visual, cy - SystemParameters.VirtualScreenTop - RadialVisual.Dim / 2);

            // gentle fade/settle-in for the slices (the glass itself is there immediately)
            visual.RenderTransformOrigin = new Point(0.5, 0.5);
            var scale = new ScaleTransform(0.94, 0.94);
            visual.RenderTransform = scale;
            visual.Opacity = 0;
            var ease = new QuadraticEase { EasingMode = EasingMode.EaseOut };
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(0.94, 1, TimeSpan.FromMilliseconds(130)) { EasingFunction = ease });
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(0.94, 1, TimeSpan.FromMilliseconds(130)) { EasingFunction = ease });
            visual.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(120)));

            MouseMove += delegate(object s, MouseEventArgs e) { visual.SetHover(visual.HitIndex(e.GetPosition(visual))); };
            MouseLeftButtonUp += delegate(object s, MouseButtonEventArgs e)
            {
                int i = visual.HitIndex(e.GetPosition(visual));
                if (i >= 0) { Chosen = visual.TargetAt(i); }
                Close();
            };
            MouseRightButtonUp += delegate { Close(); };
            KeyDown += delegate(object s, KeyEventArgs e) { if (e.Key == Key.Escape) Close(); };
            Deactivated += delegate { if (shown.ElapsedMilliseconds > 400) Close(); };
            Loaded += delegate
            {
                Activate();
                SetForegroundWindow(new WindowInteropHelper(this).Handle);
                Focus();
                // highlight whatever is already under the pointer
                visual.SetHover(visual.HitIndex(Mouse.GetPosition(visual)));
            };
        }
    }

    // ------------------------------------------------------------------ settings
    static class Settings
    {
        public static readonly string Dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RightClickConverter");
        static string IniPath { get { return Path.Combine(Dir, "radial.ini"); } }
        public static readonly string[] Presets = { "Ctrl+Alt+C", "Ctrl+Alt+Space", "Ctrl+Shift+Space", "Win+Shift+C" };
        public const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        public const string RunName = "RightClickConverterRadial";

        public static string Hotkey = "Ctrl+Alt+C";

        public static void Load()
        {
            try
            {
                if (!File.Exists(IniPath)) return;
                foreach (string line in File.ReadAllLines(IniPath))
                {
                    int eq = line.IndexOf('=');
                    if (eq > 0 && line.Substring(0, eq).Trim().ToLowerInvariant() == "hotkey") Hotkey = line.Substring(eq + 1).Trim();
                }
            }
            catch { }
        }

        public static void Save()
        {
            try { Directory.CreateDirectory(Dir); File.WriteAllText(IniPath, "hotkey=" + Hotkey + Environment.NewLine); } catch { }
        }

        public static bool Parse(string s, out uint mods, out uint vk)
        {
            mods = 0; vk = 0;
            foreach (string raw in s.Split('+'))
            {
                string p = raw.Trim().ToLowerInvariant();
                if (p == "ctrl" || p == "control") mods |= 0x2;
                else if (p == "alt") mods |= 0x1;
                else if (p == "shift") mods |= 0x4;
                else if (p == "win") mods |= 0x8;
                else
                {
                    Key k;
                    if (!Enum.TryParse<Key>(raw.Trim(), true, out k)) return false;
                    vk = (uint)KeyInterop.VirtualKeyFromKey(k);
                }
            }
            return vk != 0 && mods != 0;
        }

        public static bool GetAutostart()
        {
            try
            {
                using (var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunKey)) { return k != null && k.GetValue(RunName) != null; }
            }
            catch { return false; }
        }

        public static void SetAutostart(bool on)
        {
            try
            {
                using (var k = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (on) k.SetValue(RunName, "\"" + Process.GetCurrentProcess().MainModule.FileName + "\"");
                    else k.DeleteValue(RunName, false);
                }
            }
            catch { }
        }
    }

    // ------------------------------------------------------------------ hand a right-click request to the running tray app
    static class Ipc
    {
        public const int CopyData = 0x004A;
        public const string WindowName = "RadialConvertMsg";

        [StructLayout(LayoutKind.Sequential)] struct COPYDATASTRUCT { public IntPtr dwData; public int cbData; public IntPtr lpData; }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, ref COPYDATASTRUCT c);
        [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(int pid);

        // true if a running tray app accepted the files (it then shows the ring instantly)
        public static bool SendToTray(string[] files)
        {
            IntPtr h = FindWindowEx(new IntPtr(-3), IntPtr.Zero, null, WindowName);   // HWND_MESSAGE children
            if (h == IntPtr.Zero) return false;
            string payload = string.Join("\n", files);
            IntPtr p = Marshal.StringToHGlobalUni(payload);
            try
            {
                AllowSetForegroundWindow(-1);      // let the tray app take focus for the ring
                var c = new COPYDATASTRUCT { dwData = new IntPtr(0x5243), cbData = (payload.Length + 1) * 2, lpData = p };
                return SendMessage(h, CopyData, IntPtr.Zero, ref c) != IntPtr.Zero;
            }
            finally { Marshal.FreeHGlobal(p); }
        }

        public static string[] Read(IntPtr lParam)
        {
            var c = (COPYDATASTRUCT)Marshal.PtrToStructure(lParam, typeof(COPYDATASTRUCT));
            string s = Marshal.PtrToStringUni(c.lpData, Math.Max(0, c.cbData / 2 - 1));
            return s.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
        }
    }

    // ------------------------------------------------------------------ the tray app
    class TrayApp : Application
    {
        const int HotkeyId = 0x5243;
        [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);

        HwndSource msgWindow;
        System.Windows.Forms.NotifyIcon tray;
        RadialWindow open;
        readonly string appDir = AppDomain.CurrentDomain.BaseDirectory;

        public void Start()
        {
            ShutdownMode = ShutdownMode.OnExplicitShutdown;
            DispatcherUnhandledException += delegate(object s, DispatcherUnhandledExceptionEventArgs e) { e.Handled = true; };
            Settings.Load();

            var p = new HwndSourceParameters(Ipc.WindowName) { ParentWindow = new IntPtr(-3), Width = 0, Height = 0 };  // HWND_MESSAGE
            msgWindow = new HwndSource(p);
            msgWindow.AddHook(WndProc);

            BuildTray();
            if (!RegisterCurrentHotkey())
                tray.ShowBalloonTip(5000, "Radial Convert", "The hotkey " + Settings.Hotkey + " is already used by another program. Pick another one from the tray icon menu.", System.Windows.Forms.ToolTipIcon.Warning);
            else if (!File.Exists(Path.Combine(Settings.Dir, "radial.ini")))
            {
                Settings.Save();
                tray.ShowBalloonTip(5000, "Radial Convert is running", "Select a file in File Explorer and press " + Settings.Hotkey + ".", System.Windows.Forms.ToolTipIcon.Info);
            }
        }

        bool RegisterCurrentHotkey()
        {
            UnregisterHotKey(msgWindow.Handle, HotkeyId);
            uint mods, vk;
            if (!Settings.Parse(Settings.Hotkey, out mods, out vk)) return false;
            return RegisterHotKey(msgWindow.Handle, HotkeyId, mods | 0x4000, vk);   // 0x4000 = no auto-repeat
        }

        IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == 0x0312 && wParam.ToInt32() == HotkeyId)
            {
                handled = true;
                if (open != null) { open.Close(); return IntPtr.Zero; }   // pressing it again closes the menu
                Dispatcher.BeginInvoke(new Action(ShowMenu));
            }
            else if (msg == Ipc.CopyData)
            {
                // a right-click "Convert to..." request from RadialMenu.exe --pick; answer at once, show the ring afterwards
                handled = true;
                string[] clicked = Ipc.Read(lParam);
                Dispatcher.BeginInvoke(new Action(delegate { ShowMenu(ResolveClicked(clicked)); }));
                return new IntPtr(1);
            }
            return IntPtr.Zero;
        }

        // If the clicked file is part of a multi-selection in Explorer, use the whole selection (like the hotkey does).
        List<string> ResolveClicked(string[] fileArgs)
        {
            List<string> clicked = fileArgs.Where(a => File.Exists(a)).ToList();
            List<string> selected = Selection.Get();
            bool inSelection = clicked.Count > 0 && selected.Count > 0 &&
                clicked.All(c => selected.Any(s => string.Equals(s, c, StringComparison.OrdinalIgnoreCase)));
            return inSelection ? selected : clicked;
        }

        bool errorOpen;

        // Modal error box in the middle of the screen, on top of everything; stays until the user clicks OK.
        void ShowError(string title, string text, bool warning)
        {
            if (errorOpen) return;          // don't stack boxes if the hotkey is pressed again
            errorOpen = true;
            // a tiny invisible always-on-top owner at the centre of the screen under the pointer, so the box centres there
            var owner = new Window
            {
                WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent,
                ShowInTaskbar = false, Topmost = true, Width = 1, Height = 1
            };
            try
            {
                var scr = System.Windows.Forms.Screen.FromPoint(System.Windows.Forms.Cursor.Position);
                IntPtr h = new WindowInteropHelper(owner).EnsureHandle();
                Matrix fromDev = HwndSource.FromHwnd(h).CompositionTarget.TransformFromDevice;
                Point c = fromDev.Transform(new Point(scr.Bounds.Left + scr.Bounds.Width / 2.0, scr.Bounds.Top + scr.Bounds.Height / 2.0));
                owner.Left = c.X; owner.Top = c.Y;
                owner.Show();
                MessageBox.Show(owner, text, title, MessageBoxButton.OK, warning ? MessageBoxImage.Warning : MessageBoxImage.Information);
            }
            catch { }
            finally
            {
                try { owner.Close(); } catch { }
                errorOpen = false;
            }
        }

        bool pickMode;      // started from the right-click menu: show the ring once, convert, then exit

        string AgainText { get { return pickMode ? "try again" : "press " + Settings.Hotkey + " again"; } }

        // Right-click entry: "RadialMenu.exe --pick <file> ..."
        public void StartPick(string[] fileArgs)
        {
            pickMode = true;
            ShutdownMode = ShutdownMode.OnExplicitShutdown;
            DispatcherUnhandledException += delegate(object s, DispatcherUnhandledExceptionEventArgs e) { e.Handled = true; };
            Settings.Load();

            List<string> files = ResolveClicked(fileArgs);

            Dispatcher.BeginInvoke(new Action(delegate
            {
                ShowMenu(files);
                if (open == null) Shutdown();       // an error box was shown (or nothing to do): we're finished
            }));
        }

        void ShowMenu() { ShowMenu(null); }       // hotkey: use whatever is selected in Explorer

        void ShowMenu(List<string> given)
        {
            if (open != null || errorOpen) return;      // already showing something (e.g. several right-click requests at once)
            List<string> files = given ?? Selection.Get();
            if (files.Count == 0)
            {
                ShowError("Nothing selected", "Select a file in File Explorer (or on the Desktop) first, then press " + Settings.Hotkey + ".", false);
                return;
            }
            // all selected files must be the same type (e.g. all images); otherwise say so instead of converting only some of them
            List<string> kindsSelected = files.Select(f => Routing.KindFor(Path.GetExtension(f).TrimStart('.')) ?? "unsupported").Distinct().ToList();
            if (kindsSelected.Count > 1)
            {
                string names = string.Join(" and ", kindsSelected.Select(k => Routing.PluralName(k)).ToArray());
                ShowError("Select files of one type",
                    "You selected " + names + " together.\n\nPlease select only one type of file (for example, only images), then " + AgainText + ".", true);
                return;
            }

            string first = files[0];
            string ext = Path.GetExtension(first).TrimStart('.');
            string kind = Routing.KindFor(ext);
            if (kind == null)
            {
                ShowError("File type not supported", "." + ext + " files are not supported yet.", true);
                return;
            }
            List<string> offer = Routing.Offer(ext);
            if (offer.Count == 0)
            {
                ShowError("Converter not installed", "The programs needed to convert ." + ext + " files are not installed.\n\nRun Install.bat again to install them.", true);
                return;
            }
            var batch = files;   // already checked: every file is the same type
            string title = files.Count == 1 ? Path.GetFileName(first) : (batch.Count + " files");

            var w = new RadialWindow(offer, kind, title);
            open = w;
            w.Closed += delegate
            {
                open = null;
                if (w.Chosen != null) Convert(batch, w.Chosen);
                if (pickMode) Shutdown();
            };
            w.Present();
        }

        void Convert(List<string> files, string target)
        {
            string vbs = Path.Combine(appDir, "Launch.vbs");
            if (target == "resize")
            {
                // one launch for the whole selection, so the resize options are asked only once
                var cmd = new System.Text.StringBuilder("\"" + vbs + "\" \"" + files[0] + "\" \"resize\"");
                for (int i = 1; i < files.Count; i++) cmd.Append(" \"" + files[i] + "\"");
                try { Process.Start(new ProcessStartInfo("wscript.exe", cmd.ToString()) { UseShellExecute = false }); } catch { }
                return;
            }
            foreach (string f in files)
            {
                if (Routing.Normalize(Path.GetExtension(f).TrimStart('.')) == target) continue;
                try
                {
                    Process.Start(new ProcessStartInfo("wscript.exe", "\"" + vbs + "\" \"" + f + "\" \"" + target + "\"") { UseShellExecute = false });
                }
                catch { }
                Thread.Sleep(250);
            }
        }

        void BuildTray()
        {
            tray = new System.Windows.Forms.NotifyIcon();
            tray.Icon = MakeIcon();
            tray.Text = "Radial Convert (" + Settings.Hotkey + ")";
            var menu = new System.Windows.Forms.ContextMenuStrip();

            var hk = new System.Windows.Forms.ToolStripMenuItem("Hotkey");
            foreach (string preset in Settings.Presets)
            {
                string pr = preset;
                var it = new System.Windows.Forms.ToolStripMenuItem(pr) { Checked = string.Equals(pr, Settings.Hotkey, StringComparison.OrdinalIgnoreCase) };
                it.Click += delegate
                {
                    string old = Settings.Hotkey;
                    Settings.Hotkey = pr;
                    if (RegisterCurrentHotkey())
                    {
                        Settings.Save();
                        tray.Text = "Radial Convert (" + pr + ")";
                        foreach (System.Windows.Forms.ToolStripMenuItem o in hk.DropDownItems) o.Checked = (o.Text == pr);
                    }
                    else
                    {
                        Settings.Hotkey = old; RegisterCurrentHotkey();
                        tray.ShowBalloonTip(3000, "Radial Convert", pr + " is already used by another program.", System.Windows.Forms.ToolTipIcon.Warning);
                    }
                };
                hk.DropDownItems.Add(it);
            }
            menu.Items.Add(hk);

            var auto = new System.Windows.Forms.ToolStripMenuItem("Start with Windows") { Checked = Settings.GetAutostart() };
            auto.Click += delegate { Settings.SetAutostart(!auto.Checked); auto.Checked = Settings.GetAutostart(); };
            menu.Items.Add(auto);

            menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
            var exit = new System.Windows.Forms.ToolStripMenuItem("Exit");
            exit.Click += delegate { Quit(); };
            menu.Items.Add(exit);
            tray.ContextMenuStrip = menu;
            tray.Visible = true;
        }

        void Quit()
        {
            try { UnregisterHotKey(msgWindow.Handle, HotkeyId); } catch { }
            tray.Visible = false;
            tray.Dispose();
            Shutdown();
        }

        static System.Drawing.Icon MakeIcon()
        {
            using (var bmp = new System.Drawing.Bitmap(32, 32))
            using (var g = System.Drawing.Graphics.FromImage(bmp))
            {
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.Clear(System.Drawing.Color.Transparent);
                using (var bg = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(255, 35, 40, 51))) g.FillEllipse(bg, 1, 1, 30, 30);
                using (var blue = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(255, 59, 130, 246)))
                using (var pen = new System.Drawing.Pen(System.Drawing.Color.FromArgb(255, 232, 235, 242), 2))
                {
                    g.FillPie(blue, 3, 3, 26, 26, -90, 60);
                    g.DrawEllipse(pen, 3, 3, 26, 26);
                    g.FillEllipse(new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(255, 35, 40, 51)), 10, 10, 12, 12);
                }
                return System.Drawing.Icon.FromHandle(bmp.GetHicon());
            }
        }
    }

    // ------------------------------------------------------------------ entry point
    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            // test helper: render the menu to a PNG.   RadialMenu.exe --snapshot out.png [kind] [hoverIndex]
            if (args.Length >= 2 && args[0] == "--snapshot")
            {
                string kind = args.Length > 2 ? args[2] : "image";
                int hov = args.Length > 3 ? int.Parse(args[3]) : -1;
                var targets = Routing.TargetsFor(kind).ToList();
                var v = new RadialVisual(targets, kind, kind == "video" ? "holiday.mp4" : "photo.png", (byte)0x66);
                v.SetHover(hov);
                // busy colourful backdrop so the translucency is visible (real blur is only applied live)
                var busy = new LinearGradientBrush();
                busy.StartPoint = new Point(0, 0); busy.EndPoint = new Point(1, 1);
                busy.GradientStops.Add(new GradientStop(Color.FromRgb(0xF2, 0x9E, 0x4C), 0.0));
                busy.GradientStops.Add(new GradientStop(Color.FromRgb(0xE2, 0x4E, 0x7A), 0.35));
                busy.GradientStops.Add(new GradientStop(Color.FromRgb(0x4B, 0x6C, 0xD8), 0.7));
                busy.GradientStops.Add(new GradientStop(Color.FromRgb(0x3A, 0xC7, 0xB0), 1.0));
                var bg = new Border { Background = busy, Child = v, Width = RadialVisual.Dim, Height = RadialVisual.Dim };
                bg.Measure(new System.Windows.Size(RadialVisual.Dim, RadialVisual.Dim));
                bg.Arrange(new Rect(0, 0, RadialVisual.Dim, RadialVisual.Dim));
                bg.UpdateLayout();
                int px = (int)(RadialVisual.Dim * 2);
                var rtb = new RenderTargetBitmap(px, px, 192, 192, PixelFormats.Pbgra32);
                rtb.Render(bg);
                var enc = new PngBitmapEncoder();
                enc.Frames.Add(BitmapFrame.Create(rtb));
                using (var fs = File.Create(args[1])) enc.Save(fs);
                return 0;
            }

            // test helper: after 4 seconds, write the files selected in the foreground Explorer window.
            //   RadialMenu.exe --print-selection out.txt
            if (args.Length >= 2 && args[0] == "--print-selection")
            {
                Thread.Sleep(4000);
                var lines = new List<string>(Selection.Get());
                lines.Add("--- diagnostics ---");
                lines.AddRange(Selection.Diagnostics());
                File.WriteAllLines(args[1], lines.ToArray());
                return 0;
            }

            // right-click entry:   RadialMenu.exe --pick "<file>" ["<file>" ...]
            if (args.Length >= 2 && args[0] == "--pick")
            {
                // fast path: the tray app is already running, so let it show the ring
                if (Ipc.SendToTray(args.Skip(1).ToArray())) return 0;

                // otherwise show the ring from this process
                bool first;
                // Explorer starts one process per selected file; only the first shows the ring
                using (var pickMutex = new Mutex(true, @"Local\RightClickConverterPick", out first))
                {
                    if (!first) return 0;
                    var pick = new TrayApp();
                    pick.StartPick(args.Skip(1).ToArray());
                    pick.Run();
                }
                return 0;
            }

            bool created;
            using (var mutex = new Mutex(true, @"Local\RightClickConverterRadial", out created))
            {
                if (!created) return 0;     // already running
                var app = new TrayApp();
                app.Start();
                app.Run();
            }
            return 0;
        }
    }
}
