import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { Settings as SettingsIcon, Folder, Server, Plus, Play, Square } from "lucide-react";
import { useTranslation } from "react-i18next";

type View = "profiles" | "hosts" | "settings" | "logs";

interface Profile {
  id: string;
  name: string;
  ssh_host_alias: string;
  forwards: PortForward[];
  behavior: { enabled: boolean; auto_reconnect: boolean; auto_start: boolean };
}

interface PortForward {
  id: string;
  local_host: string;
  local_port: number;
  remote_host: string;
  remote_port: number;
  label?: string;
}

export default function App() {
  const { t, i18n } = useTranslation();
  const [view, setView] = useState<View>("profiles");
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [theme, setTheme] = useState<"system" | "light" | "dark">("system");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadProfiles();
    loadSettings();
  }, []);

  useEffect(() => {
    applyTheme(theme);
  }, [theme]);

  async function loadProfiles() {
    try {
      const result = await invoke<Profile[]>("list_profiles");
      setProfiles(result);
    } catch (e) {
      setError(String(e));
    }
  }

  async function loadSettings() {
    try {
      const s = await invoke<{ general: { theme: string } }>("get_settings");
      setTheme(s.general.theme as "system" | "light" | "dark");
    } catch (e) {
      console.error("Failed to load settings:", e);
    }
  }

  function applyTheme(theme: string) {
    const root = document.documentElement;
    const effective = theme === "system"
      ? (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")
      : theme;
    root.classList.toggle("dark", effective === "dark");
  }

  async function startProfile(profileId: string) {
    try {
      await invoke("start_tunnel", { profileId });
    } catch (e) {
      setError(String(e));
    }
  }

  async function stopProfile(profileId: string) {
    try {
      await invoke("stop_tunnel", { profileId });
    } catch (e) {
      setError(String(e));
    }
  }

  return (
    <div className="flex h-screen bg-background text-foreground">
      {/* Sidebar */}
      <aside className="w-48 border-r border-border bg-card flex flex-col">
        <div className="p-4 border-b border-border">
          <h1 className="text-lg font-semibold">Janus SSH</h1>
        </div>
        <nav className="flex-1 p-2 space-y-1">
          <NavItem icon={<Server size={16} />} active={view === "profiles"} onClick={() => setView("profiles")}>
            {t("nav.profiles")}
          </NavItem>
          <NavItem icon={<Folder size={16} />} active={view === "hosts"} onClick={() => setView("hosts")}>
            {t("nav.hosts")}
          </NavItem>
          <NavItem icon={<SettingsIcon size={16} />} active={view === "settings"} onClick={() => setView("settings")}>
            {t("nav.settings")}
          </NavItem>
        </nav>
      </aside>

      {/* Main */}
      <main className="flex-1 overflow-auto">
        {error && (
          <div className="m-4 p-3 bg-destructive/10 border border-destructive text-destructive rounded">
            {error}
            <button onClick={() => setError(null)} className="ml-2 underline">×</button>
          </div>
        )}

        {view === "profiles" && (
          <ProfileList
            profiles={profiles}
            onStart={startProfile}
            onStop={stopProfile}
          />
        )}
        {view === "hosts" && <HostsView />}
        {view === "settings" && (
          <SettingsView
            theme={theme}
            onThemeChange={(t: "system" | "light" | "dark") => {
              setTheme(t);
              invoke("update_settings", { settings: { general: { theme: t } } }).catch(console.error);
            }}
            onLangChange={(l: string) => i18n.changeLanguage(l)}
          />
        )}
      </main>
    </div>
  );
}

function NavItem({ icon, active, onClick, children }: any) {
  return (
    <button
      onClick={onClick}
      className={`w-full flex items-center gap-2 px-3 py-2 text-sm rounded ${
        active ? "bg-accent text-accent-foreground" : "hover:bg-accent/50"
      }`}
    >
      {icon}
      <span>{children}</span>
    </button>
  );
}

function ProfileList({ profiles, onStart, onStop }: any) {
  const { t } = useTranslation();
  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-2xl font-semibold">{t("profiles.title")}</h2>
        <button className="flex items-center gap-2 px-3 py-2 bg-primary text-primary-foreground rounded text-sm">
          <Plus size={16} /> {t("profiles.new")}
        </button>
      </div>
      <div className="space-y-3">
        {profiles.length === 0 && (
          <div className="p-8 text-center text-muted-foreground border border-dashed border-border rounded">
            {t("profiles.empty")}
          </div>
        )}
        {profiles.map((p: Profile) => (
          <div key={p.id} className="p-4 border border-border rounded bg-card">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="font-medium">{p.name}</h3>
                <p className="text-sm text-muted-foreground">@{p.ssh_host_alias}</p>
              </div>
              <div className="flex gap-2">
                <button onClick={() => onStart(p.id)} className="px-3 py-1 bg-green-600 text-white rounded text-sm flex items-center gap-1">
                  <Play size={14} /> Start
                </button>
                <button onClick={() => onStop(p.id)} className="px-3 py-1 bg-red-600 text-white rounded text-sm flex items-center gap-1">
                  <Square size={14} /> Stop
                </button>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function HostsView() {
  return <div className="p-6"><h2 className="text-2xl font-semibold">SSH Hosts</h2><p className="text-muted-foreground mt-2">Coming soon</p></div>;
}

function SettingsView({ theme, onThemeChange, onLangChange }: any) {
  const { t } = useTranslation();
  return (
    <div className="p-6 space-y-6">
      <h2 className="text-2xl font-semibold">{t("settings.title")}</h2>
      <div>
        <label className="block text-sm font-medium mb-1">{t("settings.theme")}</label>
        <select value={theme} onChange={(e) => onThemeChange(e.target.value)} className="border border-border rounded px-3 py-2 bg-background">
          <option value="system">System</option>
          <option value="light">Light</option>
          <option value="dark">Dark</option>
        </select>
      </div>
      <div>
        <label className="block text-sm font-medium mb-1">Language</label>
        <select onChange={(e) => onLangChange(e.target.value)} defaultValue="en" className="border border-border rounded px-3 py-2 bg-background">
          <option value="en">English</option>
          <option value="zh">中文</option>
        </select>
      </div>
    </div>
  );
}
