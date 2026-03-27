import { getUsers, getWaitlist } from "@/lib/queries"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { format, parseISO } from "date-fns"

export const revalidate = 60

export default async function UsersPage() {
  const [users, waitlist] = await Promise.all([getUsers(), getWaitlist()])

  const activeUsers = users.filter((u) => u.generations > 0)
  const onboardedUsers = users.filter((u) => u.onboarding_completed_at)

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-base font-normal tracking-wide">Users</h1>
        <p className="text-xs text-muted-foreground mt-0.5">
          {users.length} registered · {activeUsers.length} active · {onboardedUsers.length} onboarded
        </p>
      </div>

      <Tabs defaultValue="users">
        <TabsList className="h-7">
          <TabsTrigger value="users" className="text-xs h-6">Users ({users.length})</TabsTrigger>
          <TabsTrigger value="waitlist" className="text-xs h-6">
            Waitlist ({waitlist === null ? "N/A" : waitlist.length})
          </TabsTrigger>
        </TabsList>

        <TabsContent value="users" className="mt-4">
          <Card>
            <CardHeader>
              <CardTitle>Registered users</CardTitle>
              <CardDescription>Sorted by most generations</CardDescription>
            </CardHeader>
            <CardContent className="p-0 overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Email</TableHead>
                    <TableHead>Onboarded</TableHead>
                    <TableHead>Card variant</TableHead>
                    <TableHead>Generations</TableHead>
                    <TableHead>Success</TableHead>
                    <TableHead>Success rate</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {[...users]
                    .sort((a, b) => b.generations - a.generations)
                    .map((u) => (
                      <TableRow key={u.id}>
                        <TableCell className="font-medium">{u.email ?? u.id.slice(0, 8)}</TableCell>
                        <TableCell>
                          <span className={u.onboarding_completed_at ? "text-[oklch(0.72_0.18_142)] text-[11px]" : "text-muted-foreground text-[11px]"}>
                            {u.onboarding_completed_at ? "yes" : "no"}
                          </span>
                        </TableCell>
                        <TableCell className="text-muted-foreground text-[11px]">
                          {u.card_variant ?? "—"}
                        </TableCell>
                        <TableCell>{u.generations}</TableCell>
                        <TableCell>{u.successGenerations}</TableCell>
                        <TableCell>
                          {u.generations > 0 ? (
                            <span className={u.successGenerations / u.generations >= 0.7 ? "text-success" : "text-destructive"}>
                              {Math.round((u.successGenerations / u.generations) * 100)}%
                            </span>
                          ) : (
                            <span className="text-muted-foreground">—</span>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  {users.length === 0 && (
                    <TableRow>
                      <TableCell colSpan={6} className="text-center text-muted-foreground py-8">No users</TableCell>
                    </TableRow>
                  )}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="waitlist" className="mt-4">
          {waitlist === null ? (
            <Card>
              <CardContent className="py-12 text-center text-muted-foreground text-sm">
                <p>No <code className="text-xs bg-muted px-1 py-0.5 rounded">waitlist</code> table found in Supabase.</p>
                <p className="text-xs mt-2">Create a table with columns: <code className="bg-muted px-1 py-0.5 rounded">id, email, created_at, status</code></p>
              </CardContent>
            </Card>
          ) : (
            <Card>
              <CardHeader>
                <CardTitle>Waitlist signups</CardTitle>
                <CardDescription>{waitlist.length} emails</CardDescription>
              </CardHeader>
              <CardContent className="p-0 overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Email</TableHead>
                      <TableHead>Signed up</TableHead>
                      <TableHead>Status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {waitlist.map((w) => (
                      <TableRow key={w.id}>
                        <TableCell className="font-medium">{w.email}</TableCell>
                        <TableCell className="text-muted-foreground">
                          {w.created_at ? format(parseISO(w.created_at), "MMM dd, yyyy") : "—"}
                        </TableCell>
                        <TableCell className="text-muted-foreground text-[11px]">
                          {w.status ?? "pending"}
                        </TableCell>
                      </TableRow>
                    ))}
                    {waitlist.length === 0 && (
                      <TableRow>
                        <TableCell colSpan={3} className="text-center text-muted-foreground py-8">No signups yet</TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}
        </TabsContent>
      </Tabs>
    </div>
  )
}
