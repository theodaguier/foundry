import { useEffect } from "react";
import { Routes, Route, useNavigate } from "react-router-dom";
import { useAppStore } from "./stores/app-store";
import AuthContainer from "./pages/auth/AuthContainer";
import Welcome from "./pages/Welcome";
import PluginLibrary from "./pages/PluginLibrary";
import Prompt from "./pages/Prompt";
import QuickOptions from "./pages/QuickOptions";
import GenerationProgress from "./pages/GenerationProgress";
import Result from "./pages/Result";
import ErrorPage from "./pages/Error";
import Refine from "./pages/Refine";
import Settings from "./pages/Settings";
import BuildQueue from "./pages/BuildQueue";

function LaunchScreen() {
  return (
    <div className="flex flex-col items-center justify-center h-full gap-4">
      <div className="text-[var(--color-text-secondary)] text-2xl font-[ArchitypeStedelijk]">
        FOUNDRY
      </div>
      <div className="w-4 h-4 border-2 border-[var(--color-text-muted)] border-t-transparent rounded-full animate-spin" />
    </div>
  );
}

export default function App() {
  const authState = useAppStore((s) => s.authState);
  const checkSession = useAppStore((s) => s.checkSession);
  const loadPlugins = useAppStore((s) => s.loadPlugins);
  const plugins = useAppStore((s) => s.plugins);

  useEffect(() => {
    checkSession();
  }, [checkSession]);

  useEffect(() => {
    if (authState === "authenticated") {
      loadPlugins();
    }
  }, [authState, loadPlugins]);

  if (authState === "checking") {
    return <LaunchScreen />;
  }

  if (authState === "unauthenticated") {
    return <AuthContainer />;
  }

  return (
    <div className="flex flex-col h-full">
      {/* Title bar — 52px drag region matching Swift headerHeight */}
      <div
        data-tauri-drag-region
        className="h-[52px] flex items-center justify-center shrink-0"
      >
        <span className="text-[11px] font-[var(--font-mono)] text-[var(--color-text-muted)] tracking-[1.5px] uppercase">
          FOUNDRY
        </span>
      </div>

      {/* Main content */}
      <div className="flex-1 overflow-hidden">
        <Routes>
          <Route
            path="/"
            element={
              plugins.length === 0 ? <Welcome /> : <PluginLibrary />
            }
          />
          <Route path="/prompt" element={<Prompt />} />
          <Route path="/quick-options" element={<QuickOptions />} />
          <Route path="/generation" element={<GenerationProgress mode="generation" />} />
          <Route path="/refinement" element={<GenerationProgress mode="refinement" />} />
          <Route path="/refine/:pluginId" element={<Refine />} />
          <Route path="/result/:pluginId" element={<Result />} />
          <Route path="/error" element={<ErrorPage />} />
          <Route path="/queue" element={<BuildQueue />} />
          <Route path="/settings" element={<Settings />} />
        </Routes>
      </div>
    </div>
  );
}
