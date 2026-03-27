"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { LayoutDashboard, Zap, BarChart2, Users, LogOut } from "lucide-react"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarSeparator,
} from "@/components/ui/sidebar"

const nav = [
  { href: "/",            label: "Overview",    icon: LayoutDashboard },
  { href: "/generations", label: "Generations", icon: Zap },
  { href: "/pipeline",    label: "Pipeline",    icon: BarChart2 },
  { href: "/users",       label: "Users",       icon: Users },
]

export function AppSidebar() {
  const path = usePathname()

  return (
    <Sidebar collapsible="icon">
      <SidebarHeader className="px-3 py-4">
        <span className="text-[10px] tracking-[0.2em] text-muted-foreground/60 uppercase px-1">
          Foundry
        </span>
      </SidebarHeader>

      <SidebarSeparator />

      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu>
              {nav.map(({ href, label, icon: Icon }) => (
                <SidebarMenuItem key={href}>
                  <SidebarMenuButton
                    render={<Link href={href} />}
                    isActive={path === href}
                    size="sm"
                    tooltip={label}
                  >
                    <Icon className="shrink-0" />
                    <span>{label}</span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter className="pb-4">
        <SidebarSeparator />
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              render={<a href="/api/logout" />}
              size="sm"
              tooltip="Logout"
              className="text-muted-foreground hover:text-foreground"
            >
              <LogOut className="shrink-0" />
              <span>Logout</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  )
}
