using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace EasyTunnelInstaller
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new ModernInstallerForm());
        }
    }

    public class ModernInstallerForm : Form
    {
        private const string AppName = "Easy Tunnel";
        private const string AppVersion = "1.0.1";
        private const string RegistryKeyName = "EasyTunnel";

        private string defaultInstallDir;
        private bool isUpdating = false;

        private Label lblStatus;
        private ModernProgressBar progressBar;
        private ModernButton btnAction;
        private TextBox txtPath;
        private ModernCheckBox chkDesktop;
        private ModernCheckBox chkLaunch;
        private Icon appIcon;

        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();
        [DllImport("user32.dll")]
        public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);

        private const int WM_NCLBUTTONDOWN = 0xA1;
        private const int HTCAPTION = 0x2;

        public ModernInstallerForm()
        {
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.Size = new Size(580, 410);
            this.BackColor = Color.FromArgb(18, 18, 18);
            this.DoubleBuffered = true;

            defaultInstallDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Programs", "EasyTunnel");

            // 载入应用图标
            try
            {
                appIcon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            }
            catch
            {
                appIcon = SystemIcons.Application;
            }

            InitializeModernUI();
            CheckExistingInstallation();
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ClassStyle |= 0x20000; // CS_DROPSHADOW 原生阴影
                return cp;
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            // 绘制 1px 外围暗黑微边框
            using (Pen borderPen = new Pen(Color.FromArgb(38, 38, 38), 1))
            {
                g.DrawRectangle(borderPen, 0, 0, this.Width - 1, this.Height - 1);
            }

            // 顶部标题栏背景
            using (SolidBrush bgBrush = new SolidBrush(Color.FromArgb(24, 24, 24)))
            {
                g.FillRectangle(bgBrush, 1, 1, this.Width - 2, 70);
            }

            using (Pen sepPen = new Pen(Color.FromArgb(32, 32, 32), 1))
            {
                g.DrawLine(sepPen, 1, 71, this.Width - 2, 71);
            }

            // 绘制高清 Logo 图标
            if (appIcon != null)
            {
                g.DrawIcon(appIcon, new Rectangle(20, 16, 38, 38));
            }

            // 测量标题文字宽度并动态定位版本胶囊，绝对杜绝重叠！
            using (Font titleFont = new Font("Segoe UI", 12.5f, FontStyle.Bold))
            using (SolidBrush textBrush = new SolidBrush(Color.FromArgb(245, 245, 245)))
            {
                g.DrawString(AppName, titleFont, textBrush, new PointF(66, 14));
                SizeF titleSize = g.MeasureString(AppName, titleFont);

                // 版本药丸小胶囊标签紧贴文字之后
                float badgeX = 66 + titleSize.Width + 4;
                using (GraphicsPath path = GetRoundedRect(new Rectangle((int)badgeX, 17, 46, 17), 3))
                using (SolidBrush badgeBg = new SolidBrush(Color.FromArgb(34, 34, 34)))
                using (Pen badgeBorder = new Pen(Color.FromArgb(50, 50, 50), 1))
                using (Font badgeFont = new Font("Segoe UI", 8f, FontStyle.Bold))
                using (SolidBrush badgeText = new SolidBrush(Color.FromArgb(16, 185, 129)))
                {
                    g.FillPath(badgeBg, path);
                    g.DrawPath(badgeBorder, path);
                    g.DrawString("v" + AppVersion, badgeFont, badgeText, badgeX + 5, 18);
                }
            }

            // 副标题说明
            using (Font subFont = new Font("Segoe UI", 8.5f, FontStyle.Regular))
            using (SolidBrush subBrush = new SolidBrush(Color.FromArgb(135, 135, 135)))
            {
                g.DrawString("专为 Windows 开发机打造的现代化内网穿透与端口管理工具", subFont, subBrush, new PointF(67, 39));
            }
        }

        private void InitializeModernUI()
        {
            // 窗体支持按住顶部拖动
            this.MouseDown += (s, e) =>
            {
                if (e.Button == MouseButtons.Left && e.Y <= 71)
                {
                    ReleaseCapture();
                    SendMessage(this.Handle, WM_NCLBUTTONDOWN, HTCAPTION, 0);
                }
            };

            // 右上角极简关闭按钮
            Label btnClose = new Label();
            btnClose.Text = "✕";
            btnClose.Font = new Font("Segoe UI", 9f, FontStyle.Regular);
            btnClose.ForeColor = Color.FromArgb(130, 130, 130);
            btnClose.BackColor = Color.Transparent;
            btnClose.Size = new Size(36, 28);
            btnClose.Location = new Point(this.Width - 36, 1);
            btnClose.TextAlign = ContentAlignment.MiddleCenter;
            btnClose.Cursor = Cursors.Hand;
            btnClose.MouseEnter += (s, e) => { btnClose.BackColor = Color.FromArgb(239, 68, 68); btnClose.ForeColor = Color.White; };
            btnClose.MouseLeave += (s, e) => { btnClose.BackColor = Color.Transparent; btnClose.ForeColor = Color.FromArgb(130, 130, 130); };
            btnClose.Click += (s, e) => Application.Exit();
            this.Controls.Add(btnClose);

            // 右上角最小化按钮
            Label btnMin = new Label();
            btnMin.Text = "─";
            btnMin.Font = new Font("Segoe UI", 8f, FontStyle.Regular);
            btnMin.ForeColor = Color.FromArgb(130, 130, 130);
            btnMin.BackColor = Color.Transparent;
            btnMin.Size = new Size(36, 28);
            btnMin.Location = new Point(this.Width - 72, 1);
            btnMin.TextAlign = ContentAlignment.MiddleCenter;
            btnMin.Cursor = Cursors.Hand;
            btnMin.MouseEnter += (s, e) => { btnMin.BackColor = Color.FromArgb(36, 36, 36); btnMin.ForeColor = Color.White; };
            btnMin.MouseLeave += (s, e) => { btnMin.BackColor = Color.Transparent; btnMin.ForeColor = Color.FromArgb(130, 130, 130); };
            btnMin.Click += (s, e) => this.WindowState = FormWindowState.Minimized;
            this.Controls.Add(btnMin);

            // 主卡片背景面板
            Panel cardPanel = new Panel();
            cardPanel.BackColor = Color.FromArgb(24, 24, 24);
            cardPanel.Location = new Point(20, 88);
            cardPanel.Size = new Size(540, 240);
            cardPanel.Paint += (s, e) =>
            {
                using (Pen p = new Pen(Color.FromArgb(36, 36, 36), 1))
                {
                    e.Graphics.DrawRectangle(p, 0, 0, cardPanel.Width - 1, cardPanel.Height - 1);
                }
            };

            // 1. 安装路径标题
            Label lblPath = new Label();
            lblPath.Text = "安装目标路径";
            lblPath.Font = new Font("Segoe UI", 9f, FontStyle.Bold);
            lblPath.ForeColor = Color.FromArgb(225, 225, 225);
            lblPath.Location = new Point(16, 14);
            lblPath.AutoSize = true;
            cardPanel.Controls.Add(lblPath);

            // 现代集成式路径选择框容器
            Panel pathContainer = new Panel();
            pathContainer.Location = new Point(16, 36);
            pathContainer.Size = new Size(508, 32);
            pathContainer.BackColor = Color.FromArgb(14, 14, 14);
            pathContainer.Paint += (s, e) =>
            {
                using (Pen p = new Pen(Color.FromArgb(42, 42, 42), 1))
                {
                    e.Graphics.DrawRectangle(p, 0, 0, pathContainer.Width - 1, pathContainer.Height - 1);
                }
            };

            txtPath = new TextBox();
            txtPath.Text = defaultInstallDir;
            txtPath.Font = new Font("Consolas", 9f);
            txtPath.BackColor = Color.FromArgb(14, 14, 14);
            txtPath.ForeColor = Color.FromArgb(235, 235, 235);
            txtPath.BorderStyle = BorderStyle.None;
            txtPath.Location = new Point(10, 8);
            txtPath.Size = new Size(420, 18);
            pathContainer.Controls.Add(txtPath);

            ModernButton btnBrowse = new ModernButton();
            btnBrowse.Text = "更改...";
            btnBrowse.Font = new Font("Segoe UI", 8.5f);
            btnBrowse.Size = new Size(64, 24);
            btnBrowse.Location = new Point(508 - 64 - 4, 4);
            btnBrowse.NormalColor = Color.FromArgb(30, 30, 30);
            btnBrowse.HoverColor = Color.FromArgb(44, 44, 44);
            btnBrowse.TextColor = Color.FromArgb(210, 210, 210);
            btnBrowse.CornerRadius = 3;
            btnBrowse.Click += (s, e) =>
            {
                using (FolderBrowserDialog fbd = new FolderBrowserDialog())
                {
                    fbd.SelectedPath = txtPath.Text;
                    if (fbd.ShowDialog() == DialogResult.OK)
                    {
                        txtPath.Text = Path.Combine(fbd.SelectedPath, "EasyTunnel");
                    }
                }
            };
            pathContainer.Controls.Add(btnBrowse);
            cardPanel.Controls.Add(pathContainer);

            // 2. 现代选项复选框
            chkDesktop = new ModernCheckBox();
            chkDesktop.Text = "在桌面创建 Easy Tunnel 快捷方式";
            chkDesktop.Checked = true;
            chkDesktop.Location = new Point(16, 80);
            cardPanel.Controls.Add(chkDesktop);

            chkLaunch = new ModernCheckBox();
            chkLaunch.Text = "安装完成后自动启动应用";
            chkLaunch.Checked = true;
            chkLaunch.Location = new Point(16, 110);
            cardPanel.Controls.Add(chkLaunch);

            // 3. 状态提示说明
            lblStatus = new Label();
            lblStatus.Text = "就绪。点击下方按钮开始安装。升级安装将自动保留所有隧道配置与 Token 凭据。";
            lblStatus.Font = new Font("Segoe UI", 8.5f);
            lblStatus.ForeColor = Color.FromArgb(120, 120, 120);
            lblStatus.Location = new Point(16, 146);
            lblStatus.Size = new Size(508, 40);
            cardPanel.Controls.Add(lblStatus);

            // 4. 极细平滑进度条
            progressBar = new ModernProgressBar();
            progressBar.Location = new Point(16, 214);
            progressBar.Size = new Size(508, 4);
            progressBar.Visible = false;
            cardPanel.Controls.Add(progressBar);

            this.Controls.Add(cardPanel);

            // 底部操作按钮 (高质感科技蓝现代按钮)
            btnAction = new ModernButton();
            btnAction.Text = "立即安装";
            btnAction.Size = new Size(120, 36);
            btnAction.Location = new Point(this.Width - 20 - 120, 348);
            btnAction.NormalColor = Color.FromArgb(59, 130, 246);
            btnAction.HoverColor = Color.FromArgb(37, 99, 235);
            btnAction.TextColor = Color.White;
            btnAction.Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
            btnAction.Click += BtnAction_Click;
            this.Controls.Add(btnAction);
        }

        private void CheckExistingInstallation()
        {
            try
            {
                if (File.Exists(Path.Combine(defaultInstallDir, "easy_tunnel.exe")))
                {
                    isUpdating = true;
                    btnAction.Text = "更新安装";
                    lblStatus.Text = "检测到已安装 Easy Tunnel，将执行无损覆盖更新。所有已有隧道配置与 Token 凭据均安全保留。";
                    lblStatus.ForeColor = Color.FromArgb(52, 211, 153);
                }
            }
            catch { }
        }

        private void BtnAction_Click(object sender, EventArgs e)
        {
            btnAction.Enabled = false;
            txtPath.Enabled = false;
            chkDesktop.Enabled = false;
            chkLaunch.Enabled = false;
            progressBar.Visible = true;

            string targetDir = txtPath.Text.Trim();
            bool createDesktop = chkDesktop.Checked;
            bool launchAfter = chkLaunch.Checked;

            Thread worker = new Thread(() =>
            {
                try
                {
                    UpdateStatus("正在退出后台运行的实例...");
                    KillRunningProcess();

                    UpdateStatus("正在准备目标目录...");
                    if (!Directory.Exists(targetDir))
                    {
                        Directory.CreateDirectory(targetDir);
                    }

                    UpdateStatus("正在解压核心应用组件...");
                    ExtractEmbeddedPackage(targetDir);

                    UpdateStatus("正在注册系统入口与快捷方式...");
                    CreateShortcuts(targetDir, createDesktop);
                    RegisterUninstall(targetDir);

                    this.Invoke(new Action(() =>
                    {
                        progressBar.Value = 100;
                        lblStatus.Text = isUpdating ? "更新安装成功！" : "安装完成！";
                        lblStatus.ForeColor = Color.FromArgb(52, 211, 153);
                        btnAction.Text = "完成";
                        btnAction.Enabled = true;
                        btnAction.Click -= BtnAction_Click;
                        btnAction.Click += (s, args) =>
                        {
                            if (launchAfter)
                            {
                                LaunchApp(targetDir);
                            }
                            Application.Exit();
                        };
                    }));
                }
                catch (Exception ex)
                {
                    this.Invoke(new Action(() =>
                    {
                        progressBar.Visible = false;
                        lblStatus.Text = "安装失败: " + ex.Message;
                        lblStatus.ForeColor = Color.FromArgb(239, 68, 68);
                        btnAction.Enabled = true;
                    }));
                }
            });
            worker.IsBackground = true;
            worker.Start();
        }

        private void UpdateStatus(string text)
        {
            if (this.InvokeRequired)
            {
                this.Invoke(new Action<string>(UpdateStatus), text);
                return;
            }
            lblStatus.Text = text;
        }

        private void KillRunningProcess()
        {
            try
            {
                Process[] procs = Process.GetProcessesByName("easy_tunnel");
                foreach (var p in procs)
                {
                    try
                    {
                        p.Kill();
                        p.WaitForExit(3000);
                    }
                    catch { }
                }
            }
            catch { }
        }

        private void ExtractEmbeddedPackage(string targetDir)
        {
            var assembly = Assembly.GetExecutingAssembly();
            using (Stream stream = assembly.GetManifestResourceStream("app_package.zip"))
            {
                if (stream == null)
                {
                    throw new Exception("安装程序内未检测到嵌入的核心资源包。");
                }
                string tempZip = Path.Combine(Path.GetTempPath(), "EasyTunnel_pkg_" + Guid.NewGuid().ToString("N") + ".zip");
                try
                {
                    using (FileStream fs = new FileStream(tempZip, FileMode.Create, FileAccess.Write))
                    {
                        stream.CopyTo(fs);
                    }

                    using (ZipArchive archive = ZipFile.OpenRead(tempZip))
                    {
                        int count = archive.Entries.Count;
                        int idx = 0;
                        foreach (ZipArchiveEntry entry in archive.Entries)
                        {
                            idx++;
                            int progress = (int)((double)idx / count * 95);
                            this.Invoke(new Action(() => { progressBar.Value = progress; }));

                            string destinationPath = Path.GetFullPath(Path.Combine(targetDir, entry.FullName));
                            if (!destinationPath.StartsWith(Path.GetFullPath(targetDir), StringComparison.OrdinalIgnoreCase))
                            {
                                continue;
                            }

                            if (string.IsNullOrEmpty(entry.Name))
                            {
                                Directory.CreateDirectory(destinationPath);
                            }
                            else
                            {
                                string parent = Path.GetDirectoryName(destinationPath);
                                if (!Directory.Exists(parent))
                                {
                                    Directory.CreateDirectory(parent);
                                }
                                entry.ExtractToFile(destinationPath, true);
                            }
                        }
                    }
                }
                finally
                {
                    try { if (File.Exists(tempZip)) File.Delete(tempZip); } catch { }
                }
            }
        }

        private void CreateShortcuts(string targetDir, bool createDesktop)
        {
            string exePath = Path.Combine(targetDir, "easy_tunnel.exe");
            if (!File.Exists(exePath)) return;

            string startMenuDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "Microsoft", "Windows", "Start Menu", "Programs");
            if (!Directory.Exists(startMenuDir)) Directory.CreateDirectory(startMenuDir);

            CreateWshShortcut(Path.Combine(startMenuDir, AppName + ".lnk"), exePath, targetDir);

            if (createDesktop)
            {
                string desktopDir = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                CreateWshShortcut(Path.Combine(desktopDir, AppName + ".lnk"), exePath, targetDir);
            }
        }

        private void CreateWshShortcut(string shortcutPath, string targetPath, string workingDir)
        {
            try
            {
                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                dynamic shell = Activator.CreateInstance(shellType);
                dynamic shortcut = shell.CreateShortcut(shortcutPath);
                shortcut.TargetPath = targetPath;
                shortcut.WorkingDirectory = workingDir;
                shortcut.Description = AppName + " - 内网穿透管家";
                shortcut.IconLocation = targetPath + ",0";
                shortcut.Save();
            }
            catch { }
        }

        private void RegisterUninstall(string targetDir)
        {
            try
            {
                string exePath = Path.Combine(targetDir, "easy_tunnel.exe");
                string uninstallerPath = Path.Combine(targetDir, "Uninstall.cmd");

                CreateUninstallerScript(targetDir);

                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\" + RegistryKeyName))
                {
                    if (key != null)
                    {
                        key.SetValue("DisplayName", AppName);
                        key.SetValue("DisplayVersion", AppVersion);
                        key.SetValue("Publisher", "Easy Tunnel");
                        key.SetValue("DisplayIcon", exePath + ",0");
                        key.SetValue("InstallLocation", targetDir);
                        key.SetValue("UninstallString", "\"" + uninstallerPath + "\"");
                        key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                        key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                        key.SetValue("EstimatedSize", 35000, RegistryValueKind.DWord);
                    }
                }
            }
            catch { }
        }

        private void CreateUninstallerScript(string targetDir)
        {
            string uninstallCmd = Path.Combine(targetDir, "Uninstall.cmd");
            string[] lines = new string[]
            {
                "@echo off",
                "chcp 65001 >nul",
                "title Easy Tunnel 卸载向导",
                "echo 正在停止运行中的 Easy Tunnel 进程...",
                "taskkill /F /IM easy_tunnel.exe >nul 2>&1",
                "taskkill /F /IM cloudflared.exe >nul 2>&1",
                "taskkill /F /IM ngrok.exe >nul 2>&1",
                "echo 正在清理系统快捷方式...",
                "del /f /q \"%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Easy Tunnel.lnk\" >nul 2>&1",
                "del /f /q \"%USERPROFILE%\\Desktop\\Easy Tunnel.lnk\" >nul 2>&1",
                "echo 正在注销注册表安装项...",
                "reg delete \"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\EasyTunnel\" /f >nul 2>&1",
                "reg delete \"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run\" /v \"EasyTunnel\" /f >nul 2>&1",
                "echo.",
                "echo Easy Tunnel 已成功卸载。",
                "echo (提示: 您的自定义隧道与凭据配置保留在 %APPDATA%\\EasyTunnel 目录下)",
                "echo.",
                "pause"
            };
            string content = string.Join("\r\n", lines) + "\r\n";
            File.WriteAllText(uninstallCmd, content, new System.Text.UTF8Encoding(true));
        }

        private void LaunchApp(string targetDir)
        {
            try
            {
                string exePath = Path.Combine(targetDir, "easy_tunnel.exe");
                ProcessStartInfo psi = new ProcessStartInfo(exePath);
                psi.WorkingDirectory = targetDir;
                Process.Start(psi);
            }
            catch { }
        }

        private static GraphicsPath GetRoundedRect(Rectangle rect, int radius)
        {
            GraphicsPath path = new GraphicsPath();
            int diameter = radius * 2;
            path.AddArc(rect.X, rect.Y, diameter, diameter, 180, 90);
            path.AddArc(rect.Right - diameter, rect.Y, diameter, diameter, 270, 90);
            path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rect.X, rect.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    public class ModernButton : Control
    {
        private Color _normalColor = Color.FromArgb(59, 130, 246);
        public Color NormalColor
        {
            get { return _normalColor; }
            set { _normalColor = value; Invalidate(); }
        }

        private Color _hoverColor = Color.FromArgb(37, 99, 235);
        public Color HoverColor
        {
            get { return _hoverColor; }
            set { _hoverColor = value; Invalidate(); }
        }

        private Color _textColor = Color.White;
        public Color TextColor
        {
            get { return _textColor; }
            set { _textColor = value; Invalidate(); }
        }

        private int _cornerRadius = 4;
        public int CornerRadius
        {
            get { return _cornerRadius; }
            set { _cornerRadius = value; Invalidate(); }
        }

        private bool isHovered = false;

        public ModernButton()
        {
            SetStyle(ControlStyles.Selectable, false);
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
            this.Cursor = Cursors.Hand;
            this.DoubleBuffered = true;
        }

        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); isHovered = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); isHovered = false; Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            Color bg = this.Enabled ? (isHovered ? HoverColor : NormalColor) : Color.FromArgb(44, 44, 44);

            int r = _cornerRadius;
            using (GraphicsPath path = new GraphicsPath())
            {
                path.AddArc(0, 0, r * 2, r * 2, 180, 90);
                path.AddArc(this.Width - r * 2 - 1, 0, r * 2, r * 2, 270, 90);
                path.AddArc(this.Width - r * 2 - 1, this.Height - r * 2 - 1, r * 2, r * 2, 0, 90);
                path.AddArc(0, this.Height - r * 2 - 1, r * 2, r * 2, 90, 90);
                path.CloseFigure();

                using (SolidBrush b = new SolidBrush(bg))
                {
                    g.FillPath(b, path);
                }
            }

            TextRenderer.DrawText(g, this.Text, this.Font, this.ClientRectangle,
                this.Enabled ? TextColor : Color.FromArgb(120, 120, 120),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }
    }

    public class ModernCheckBox : Control
    {
        private bool _checked = false;
        public bool Checked
        {
            get { return _checked; }
            set { _checked = value; Invalidate(); }
        }

        public ModernCheckBox()
        {
            this.Size = new Size(280, 22);
            this.Cursor = Cursors.Hand;
            this.DoubleBuffered = true;
        }

        protected override void OnClick(EventArgs e)
        {
            Checked = !Checked;
            base.OnClick(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            Rectangle boxRect = new Rectangle(0, 3, 15, 15);

            if (_checked)
            {
                using (SolidBrush bg = new SolidBrush(Color.FromArgb(59, 130, 246)))
                using (GraphicsPath p = new GraphicsPath())
                {
                    int r = 3;
                    p.AddArc(boxRect.X, boxRect.Y, r * 2, r * 2, 180, 90);
                    p.AddArc(boxRect.Right - r * 2, boxRect.Y, r * 2, r * 2, 270, 90);
                    p.AddArc(boxRect.Right - r * 2, boxRect.Bottom - r * 2, r * 2, r * 2, 0, 90);
                    p.AddArc(boxRect.X, boxRect.Bottom - r * 2, r * 2, r * 2, 90, 90);
                    p.CloseFigure();
                    g.FillPath(bg, p);
                }

                using (Pen checkPen = new Pen(Color.White, 1.8f))
                {
                    g.DrawLines(checkPen, new Point[] {
                        new Point(boxRect.X + 3, boxRect.Y + 7),
                        new Point(boxRect.X + 6, boxRect.Y + 11),
                        new Point(boxRect.X + 12, boxRect.Y + 4)
                    });
                }
            }
            else
            {
                using (Pen border = new Pen(Color.FromArgb(60, 60, 60), 1.2f))
                using (SolidBrush bg = new SolidBrush(Color.FromArgb(16, 16, 16)))
                {
                    g.FillRectangle(bg, boxRect);
                    g.DrawRectangle(border, boxRect);
                }
            }

            using (Font f = new Font("Segoe UI", 8.8f))
            using (SolidBrush textBrush = new SolidBrush(Color.FromArgb(220, 220, 220)))
            {
                g.DrawString(this.Text, f, textBrush, new PointF(22, 2));
            }
        }
    }

    public class ModernProgressBar : Control
    {
        private int _value = 0;
        public int Value
        {
            get { return _value; }
            set { _value = Math.Min(100, Math.Max(0, value)); Invalidate(); }
        }

        public ModernProgressBar()
        {
            this.Size = new Size(300, 4);
            this.DoubleBuffered = true;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            using (SolidBrush bg = new SolidBrush(Color.FromArgb(32, 32, 32)))
            {
                g.FillRectangle(bg, 0, 0, this.Width, this.Height);
            }

            if (_value > 0)
            {
                int w = (int)((double)_value / 100 * this.Width);
                using (SolidBrush fg = new SolidBrush(Color.FromArgb(16, 185, 129)))
                {
                    g.FillRectangle(fg, 0, 0, w, this.Height);
                }
            }
        }
    }
}
