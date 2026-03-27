import {
  SidebarInset,
  SidebarProvider,
  SidebarTrigger,
} from "@/components/ui/sidebar"
import { AppSidebar } from "@/components/app-sidebar"
import { TooltipProvider } from "@/components/ui/tooltip"

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return (
    <TooltipProvider>
      <SidebarProvider>
        <AppSidebar />
        <SidebarInset className="flex flex-col min-h-0">
          <header className="flex h-9 shrink-0 items-center gap-3 border-b border-border/60 px-4">
            <SidebarTrigger className="h-6 w-6 text-muted-foreground hover:text-foreground" />
            <span className="text-[10px] tracking-[0.15em] text-muted-foreground/50 uppercase">
              Foundry Dashboard
            </span>
          </header>
          <div className="flex-1 overflow-auto p-5">
            {children}
          </div>
        </SidebarInset>
      </SidebarProvider>
    </TooltipProvider>
  )
}
