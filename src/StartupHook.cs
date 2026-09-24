using System;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.Loader;
using HarmonyLib;
using OpenTK.Windowing.GraphicsLibraryFramework;
using Vintagestory.Client.Gui;
using Vintagestory.Client.NoObf;

/// <summary>
/// .NET startup hook for the Vintage Story client (DOTNET_STARTUP_HOOKS). Runs before the
/// game's Main: selects GLFW's Wayland backend when the session is a Wayland one, and guards
/// the loading screen against the uncompiled-GUI-shader crash that backend exposes.
/// </summary>
internal static class StartupHook
{
    public static void Initialize()
    {
        // Startup hooks do not probe the game's directories, and this method must not touch
        // any game or OpenTK type until the resolver is in place.
        string root = AppContext.BaseDirectory;
        AssemblyLoadContext.Default.Resolving += (context, name) =>
        {
            foreach (string dir in new[] { root, Path.Combine(root, "Lib") })
            {
                string path = Path.Combine(dir, name.Name + ".dll");
                if (File.Exists(path))
                {
                    return context.LoadFromAssemblyPath(path);
                }
            }

            return null;
        };

        // A game update can move what these touch; log it and let the game start anyway.
        string platform;
        try
        {
            platform = Environment.GetEnvironmentVariable("VS_WAYLAND") == "0"
                ? "left to the game (VS_WAYLAND=0)"
                : string.IsNullOrEmpty(Environment.GetEnvironmentVariable("WAYLAND_DISPLAY"))
                    ? "left to the game (not a Wayland session)"
                    : SelectWayland();
        }
        catch (Exception e)
        {
            platform = "not selected (" + e.Message + ")";
        }

        string guard;
        try
        {
            guard = $"on {PatchLoadingScreen()} methods";
        }
        catch (Exception e)
        {
            guard = "failed (" + e.Message + ")";
        }

        File.AppendAllText(
            Path.Combine(Path.GetDirectoryName(typeof(StartupHook).Assembly.Location)!, "hook.log"),
            $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] GLFW platform {platform}, loading-screen guard {guard}{Environment.NewLine}");
    }

    /// <summary>
    /// The game's own glfwInit does not reliably honour a platform hint set beforehand, so
    /// initialise GLFW here; the game's later glfwInit is then a no-op on the chosen backend.
    /// </summary>
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static string SelectWayland()
    {
        GLFW.InitHint(InitHintPlatform.Platform, Platform.Wayland);
        if (!GLFW.Init())
        {
            // Leave no Wayland-only hint behind, or the game's own glfwInit fails the same way.
            GLFW.InitHint(InitHintPlatform.Platform, Platform.Any);
            return "left to the game (GLFW could not start on Wayland)";
        }

        return GLFW.GetPlatform().ToString();
    }

    /// <summary>
    /// ShaderRegistry's static constructor creates ShaderPrograms.Gui without compiling it.
    /// On X11 that constructor first runs from ShaderRegistry.Load, which compiles straight
    /// away. On Wayland the compositor's initial configure makes Window_Resize call
    /// RebuildFrameBuffers, which reads ShaderRegistry.SupressShaderAndBufferReloads and runs
    /// the constructor early; loading-screen frames drawn before shaders load then Use() a
    /// GUI shader with no uniform locations and throw KeyNotFoundException('lightPosition').
    /// Skipping those draws is what vanilla already does while ShaderPrograms.Gui is null.
    /// </summary>
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static int PatchLoadingScreen()
    {
        int patched = 0;
        Harmony harmony = new("vintagestory-wayland");
        HarmonyMethod prefix = new(typeof(StartupHook).GetMethod(nameof(SkipUntilGuiShaderCompiled), BindingFlags.Static | BindingFlags.NonPublic));
        foreach (string name in new[] { "Render2DTexture", "Draw2DShadedEdges", "RenderRectangle" })
        {
            foreach (MethodInfo method in typeof(MainMenuRenderAPI).GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly))
            {
                // Only the overloads that read ShaderPrograms.Gui themselves; the others delegate to them.
                if (method.Name == name && ReadsGuiShader(method))
                {
                    harmony.Patch(method, prefix: prefix);
                    patched++;
                }
            }
        }

        return patched;
    }

    private static bool ReadsGuiShader(MethodInfo method)
    {
        FieldInfo gui = typeof(ShaderPrograms).GetField(nameof(ShaderPrograms.Gui))!;
        foreach (CodeInstruction instruction in PatchProcessor.GetOriginalInstructions(method))
        {
            if (instruction.operand is FieldInfo field && field == gui)
            {
                return true;
            }
        }

        return false;
    }

    private static bool SkipUntilGuiShaderCompiled()
    {
        ShaderProgramGui? gui = ShaderPrograms.Gui;
        return gui is null || gui.uniformLocations.Count > 0;
    }
}
