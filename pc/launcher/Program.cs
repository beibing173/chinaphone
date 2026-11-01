using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

namespace ChinaPhoneLauncher
{
    /// <summary>
    /// ChinaPhone 电脑版的 EXE 启动器。
    ///
    /// 作用：让用户双击即可运行，不用手动打开 PowerShell、不用设执行策略。
    /// 它做的就是把 pc/audit_android.ps1 以正确的参数跑起来，
    /// 并把控制台输出原样显示给用户。
    /// </summary>
    internal static class Program
    {
        private const string AppName = "ChinaPhone 手机自查工具";

        [STAThread]
        private static int Main(string[] args)
        {
            Console.OutputEncoding = Encoding.UTF8;
            Console.InputEncoding = Encoding.UTF8;

            PrintBanner();

            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = ResolveScript(exeDir);

            if (scriptPath == null || !File.Exists(scriptPath))
            {
                Console.WriteLine("[错误] 找不到审计脚本 audit_android.ps1");
                Console.WriteLine();
                Console.WriteLine("请确认目录结构如下：");
                Console.WriteLine("  ChinaPhone.exe");
                Console.WriteLine("  pc\\");
                Console.WriteLine("    audit_android.ps1");
                Console.WriteLine("    endpoint_check.ps1");
                Console.WriteLine("    DeviceAudit.Common.ps1");
                Console.WriteLine("    rules.json");
                Console.WriteLine();
                Console.WriteLine("当前目录: " + exeDir);
                Pause();
                return 2;
            }

            string psDir = Path.GetDirectoryName(scriptPath);
            string script = args.Length > 0 && args[0] == "endpoint"
                ? Path.Combine(psDir, "endpoint_check.ps1")
                : Path.Combine(psDir, "audit_android.ps1");

            if (!File.Exists(script))
            {
                Console.WriteLine("[错误] 找不到 " + Path.GetFileName(script));
                Pause();
                return 2;
            }

            Console.WriteLine("脚本: " + script);
            Console.WriteLine(new string('-', 68));
            Console.WriteLine();

            int exitCode = RunPowerShell(script, args);

            Console.WriteLine();
            Console.WriteLine(new string('-', 68));
            Console.WriteLine(exitCode == 0 ? "执行完成。" : "执行结束，退出码 " + exitCode);
            Pause();
            return exitCode;
        }

        private static string ResolveScript(string exeDir)
        {
            // 依次找几个常见布局
            string[] candidates =
            {
                Path.Combine(exeDir, "pc", "audit_android.ps1"),
                Path.Combine(exeDir, "audit_android.ps1"),
                Path.Combine(exeDir, "..", "pc", "audit_android.ps1"),
            };
            foreach (string c in candidates)
            {
                try
                {
                    string full = Path.GetFullPath(c);
                    if (File.Exists(full)) return full;
                }
                catch { }
            }
            return null;
        }

        private static int RunPowerShell(string script, string[] originalArgs)
        {
            var psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.UseShellExecute = false;
            psi.WorkingDirectory = Path.GetDirectoryName(script);

            var sb = new StringBuilder();
            sb.Append("-NoProfile -NoLogo -ExecutionPolicy Bypass -File ");
            sb.Append('"').Append(script).Append('"');

            // 透传 -Serial / -SkipAlarm 等参数（跳过第一个 "endpoint" 开关）
            int start = (originalArgs.Length > 0 && originalArgs[0] == "endpoint") ? 1 : 0;
            for (int i = start; i < originalArgs.Length; i++)
            {
                sb.Append(' ').Append(originalArgs[i]);
            }
            psi.Arguments = sb.ToString();

            try
            {
                using (Process p = Process.Start(psi))
                {
                    p.WaitForExit();
                    return p.ExitCode;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("[错误] 启动 PowerShell 失败: " + ex.Message);
                return 3;
            }
        }

        private static void PrintBanner()
        {
            string version = "1.0.0";
            try
            {
                // 注意：.NET Framework 自带的 csc.exe 只支持到 C# 5，
                // 不能用 ?. 和 ?? 链式写法，这里用传统写法。
                Assembly asm = Assembly.GetExecutingAssembly();
                object[] attrs = asm.GetCustomAttributes(
                    typeof(AssemblyInformationalVersionAttribute), false);
                if (attrs != null && attrs.Length > 0)
                {
                    AssemblyInformationalVersionAttribute iv =
                        attrs[0] as AssemblyInformationalVersionAttribute;
                    if (iv != null && !string.IsNullOrEmpty(iv.InformationalVersion))
                    {
                        version = iv.InformationalVersion;
                    }
                }
            }
            catch { }

            Console.WriteLine();
            Console.WriteLine("  " + AppName + "  v" + version);
            Console.WriteLine("  检查手机里是否存在隐蔽上报组件");
            Console.WriteLine();
            Console.WriteLine("  · 需要：手机开 USB 调试 + 数据线连电脑");
            Console.WriteLine("  · 只读检查，不修改手机任何设置");
            Console.WriteLine();
        }

        private static void Pause()
        {
            Console.WriteLine();
            Console.Write("按回车键退出…");
            try { Console.ReadLine(); } catch { }
        }
    }
}
