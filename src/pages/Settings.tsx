import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { useAppStore } from "../stores/app-store";
import { useSettingsStore } from "../stores/settings-store";
import { checkDependencies } from "../lib/commands";
import { Button, Badge, SectionLabel } from "../components/ui";
import type { DependencyStatus } from "../lib/types";

type Tab = "general" | "models" | "dependencies" | "account";
const tabItems: Tab[] = ["general", "models", "dependencies", "account"];
const tabLabels: Record<Tab, string> = { general: "General", models: "Models", dependencies: "Dependencies", account: "Account" };

export default function Settings() {
  const navigate = useNavigate();
  const [tab, setTab] = useState<Tab>("general");

  return (
    <div className="flex flex-col h-full max-w-[480px] mx-auto py-8 px-6">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-lg font-medium">Settings</h2>
        <Button variant="ghost" onClick={() => navigate("/")}>Done</Button>
      </div>

      {/* Tab bar */}
      <div className="flex mb-6 border-b border-[var(--color-border)]">
        {tabItems.map((t, i) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className="relative flex flex-col items-center"
            style={{ marginLeft: i === 0 ? 0 : 24 }}
          >
            <span className={`pb-2 text-[11px] tracking-[0.5px] font-[var(--font-mono)] transition-colors ${
              tab === t ? "text-[var(--color-text-primary)]" : "text-[var(--color-text-secondary)] hover:text-[var(--color-text-primary)]"
            }`}>
              {tabLabels[t]}
            </span>
            <div className="absolute bottom-0 left-0 right-0 h-[2px]" style={{ backgroundColor: tab === t ? "rgba(255,255,255,0.85)" : "transparent" }} />
          </button>
        ))}
      </div>

      <div className="flex-1 overflow-y-auto">
        {tab === "general" && <GeneralTab />}
        {tab === "models" && <ModelsTab />}
        {tab === "dependencies" && <DependenciesTab />}
        {tab === "account" && <AccountTab />}
      </div>
    </div>
  );
}

function GeneralTab() {
  const { appearance, setAppearance } = useSettingsStore();
  const pluginPaths = [
    { label: "AU Components", path: "~/Library/Audio/Plug-Ins/Components/" },
    { label: "VST3 Plugins", path: "~/Library/Audio/Plug-Ins/VST3/" },
    { label: "Plugin Data", path: "~/Library/Application Support/Foundry/" },
  ];

  return (
    <div className="flex flex-col gap-6">
      <section>
        <SectionLabel>Appearance</SectionLabel>
        <div className="flex rounded-md overflow-hidden border border-[var(--color-border)]">
          {(["system", "light", "dark"] as const).map((a) => (
            <button
              key={a}
              onClick={() => setAppearance(a)}
              className={`flex-1 py-2 text-[12px] capitalize transition-colors ${
                appearance === a
                  ? "bg-[var(--color-accent)] text-white"
                  : "bg-[var(--color-bg-text)] text-[var(--color-text-secondary)] hover:text-[var(--color-text-primary)]"
              }`}
            >
              {a === "system" ? "System" : a === "light" ? "Light" : "Dark"}
            </button>
          ))}
        </div>
      </section>

      <section>
        <SectionLabel>Plugin Paths</SectionLabel>
        <div className="flex flex-col divide-y divide-[var(--color-border)] border border-[var(--color-border)] rounded-md overflow-hidden">
          {pluginPaths.map((item) => (
            <div key={item.label} className="flex items-center justify-between px-3 py-2.5 bg-[var(--color-bg-text)]">
              <span className="text-[12px] text-[var(--color-text-primary)]">{item.label}</span>
              <span className="text-[11px] font-[var(--font-mono)] text-[var(--color-text-secondary)] select-text">{item.path}</span>
            </div>
          ))}
        </div>
      </section>

      <section>
        <SectionLabel>About</SectionLabel>
        <div className="flex flex-col divide-y divide-[var(--color-border)] border border-[var(--color-border)] rounded-md overflow-hidden">
          <div className="flex items-center justify-between px-3 py-2.5 bg-[var(--color-bg-text)]">
            <span className="text-[12px] text-[var(--color-text-primary)]">Version</span>
            <span className="text-[12px] text-[var(--color-text-secondary)]">1.0.0</span>
          </div>
          <div className="flex items-center justify-between px-3 py-2.5 bg-[var(--color-bg-text)]">
            <span className="text-[12px] text-[var(--color-text-primary)]">Build</span>
            <span className="text-[12px] text-[var(--color-text-secondary)]">1</span>
          </div>
        </div>
      </section>
    </div>
  );
}

function ModelsTab() {
  const { modelCatalog, loadCatalog, refreshModels, isRefreshing } = useSettingsStore();
  useEffect(() => { loadCatalog(); }, [loadCatalog]);

  return (
    <div className="flex flex-col gap-4">
      {modelCatalog.map((provider) => (
        <section key={provider.id}>
          <SectionLabel>{provider.name}</SectionLabel>
          <div className="flex flex-col divide-y divide-[var(--color-border)] border border-[var(--color-border)] rounded-md overflow-hidden">
            {provider.models.map((model) => (
              <div key={model.id} className="flex items-center gap-3 px-3 py-2.5 bg-[var(--color-bg-text)]">
                <div className="flex-1">
                  <div className="text-[12px] text-[var(--color-text-primary)]">{model.name}</div>
                  <div className="text-[11px] text-[var(--color-text-secondary)]">{model.subtitle}</div>
                </div>
                {model.default && <Badge variant="muted">Default</Badge>}
                <span className="text-[10px] font-[var(--font-mono)] text-[var(--color-text-muted)]">{model.flag}</span>
              </div>
            ))}
          </div>
        </section>
      ))}
      <Button variant="ghost" onClick={refreshModels} disabled={isRefreshing} className="self-start text-[var(--color-accent)]">
        {isRefreshing ? "Refreshing..." : "Refresh Models"}
      </Button>
    </div>
  );
}

function DependenciesTab() {
  const [deps, setDeps] = useState<DependencyStatus[]>([]);
  useEffect(() => { checkDependencies().then(setDeps).catch(() => {}); }, []);

  return (
    <div className="flex flex-col gap-4">
      <section>
        <SectionLabel>Required</SectionLabel>
        <div className="flex flex-col divide-y divide-[var(--color-border)] border border-[var(--color-border)] rounded-md overflow-hidden">
          {deps.map((dep) => (
            <div key={dep.name} className="flex items-center gap-3 px-3 py-2.5 bg-[var(--color-bg-text)]">
              <span className={`w-2 h-2 rounded-full shrink-0 ${dep.installed ? "bg-[var(--color-traffic-green)]" : "bg-[var(--color-traffic-red)]"}`} />
              <div className="flex-1 min-w-0">
                <div className="text-[12px] text-[var(--color-text-primary)]">{dep.name}</div>
                {dep.detail && <div className="text-[11px] text-[var(--color-text-secondary)] truncate">{dep.detail}</div>}
              </div>
              <Badge variant={dep.installed ? "success" : "warning"}>
                {dep.installed ? "Installed" : "Missing"}
              </Badge>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}

function AccountTab() {
  const signOut = useAppStore((s) => s.signOut);
  const userProfile = useAppStore((s) => s.userProfile);

  return (
    <div className="flex flex-col gap-4">
      {userProfile && (
        <div className="text-[12px] text-[var(--color-text-secondary)]">
          Signed in as {userProfile.email || userProfile.displayName || userProfile.id}
        </div>
      )}
      <Button variant="ghost" onClick={signOut} className="self-start text-[var(--color-traffic-red)]">Sign Out</Button>
    </div>
  );
}
