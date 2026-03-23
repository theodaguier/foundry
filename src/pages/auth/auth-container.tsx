import { useState, useRef, useEffect, useCallback } from "react";
import { useAppStore } from "@/stores/app-store"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import * as commands from "@/lib/commands"

type AuthScreen = "login" | "otp" | "signup";

export default function AuthContainer() {
  const setAuthState = useAppStore((s) => s.setAuthState);
  const [screen, setScreen] = useState<AuthScreen>("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [otpDigits, setOtpDigits] = useState<string[]>(Array(6).fill(""));
  const [isSignup, setIsSignup] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const otpRefs = useRef<(HTMLInputElement | null)[]>([]);

  const otpCode = otpDigits.join("");
  const signupValid = email.length > 0 && password.length >= 8 && password === confirmPassword;

  const switchTo = useCallback((s: AuthScreen) => {
    setErrorMessage(null);
    setOtpDigits(Array(6).fill(""));
    setScreen(s);
  }, []);

  const sendCode = useCallback(async () => {
    if (!email) return;
    setIsLoading(true);
    setErrorMessage(null);
    try {
      await commands.sendOtp(email);
      setIsSignup(false);
      switchTo("otp");
    } catch (e: any) {
      setErrorMessage(e?.toString() || "Failed to send code");
    }
    setIsLoading(false);
  }, [email, switchTo]);

  const verifyCode = useCallback(async (code: string) => {
    if (code.length !== 6) return;
    setIsLoading(true);
    setErrorMessage(null);
    try {
      await commands.verifyOtp(email, code, isSignup);
      setAuthState("authenticated");
    } catch (e: any) {
      setErrorMessage(e?.toString() || "Invalid code");
      setOtpDigits(Array(6).fill(""));
      otpRefs.current[0]?.focus();
    }
    setIsLoading(false);
  }, [email, isSignup, setAuthState]);

  const createAccount = useCallback(async () => {
    if (!signupValid) return;
    setIsLoading(true);
    setErrorMessage(null);
    try {
      await commands.signUp(email, password);
      setIsSignup(true);
      switchTo("otp");
    } catch (e: any) {
      setErrorMessage(e?.toString() || "Failed to create account");
    }
    setIsLoading(false);
  }, [email, password, signupValid, switchTo]);

  const handleOtpInput = useCallback((value: string, index: number) => {
    const filtered = value.replace(/\D/g, "");
    if (filtered.length >= 6) {
      const digits = filtered.slice(0, 6).split("");
      setOtpDigits(digits);
      otpRefs.current[5]?.focus();
      setTimeout(() => verifyCode(digits.join("")), 100);
      return;
    }
    if (!filtered) {
      const next = [...otpDigits];
      next[index] = "";
      setOtpDigits(next);
      return;
    }
    const next = [...otpDigits];
    next[index] = filtered.slice(-1);
    setOtpDigits(next);
    if (index < 5) otpRefs.current[index + 1]?.focus();
    const code = next.join("");
    if (code.length === 6) setTimeout(() => verifyCode(code), 100);
  }, [otpDigits, verifyCode]);

  const handleOtpKeyDown = useCallback((e: React.KeyboardEvent, index: number) => {
    if (e.key === "Backspace") {
      if (!otpDigits[index] && index > 0) {
        const next = [...otpDigits];
        next[index - 1] = "";
        setOtpDigits(next);
        otpRefs.current[index - 1]?.focus();
      } else {
        const next = [...otpDigits];
        next[index] = "";
        setOtpDigits(next);
      }
    }
  }, [otpDigits]);

  useEffect(() => {
    if (screen === "otp") otpRefs.current[0]?.focus();
  }, [screen]);

  const headerSubtitle = screen === "login" ? "SIGN IN TO YOUR ACCOUNT" : screen === "otp" ? "ENTER VERIFICATION CODE" : "CREATE YOUR ACCOUNT";

  return (
    <div className="flex flex-col items-center justify-center h-full bg-background">
      <div className="w-[340px] flex flex-col gap-8">
        {/* Header */}
        <div className="flex flex-col items-center gap-3">
          <div className="relative h-12 overflow-hidden">
            <span className="text-3xl font-[ArchitypeStedelijk] text-foreground opacity-50">
              FOUNDRY
            </span>
            <div className="absolute inset-0 overflow-hidden">
              <span className="text-3xl font-[ArchitypeStedelijk] text-foreground">
                FOUNDRY
              </span>
              <div className="absolute inset-0 w-10 bg-gradient-to-r from-transparent via-foreground/10 to-transparent animate-shimmer" />
            </div>
          </div>
          <span className="text-[10px] font-mono tracking-[2px] text-muted-foreground/60">
            {headerSubtitle}
          </span>
        </div>

        {/* Login */}
        {screen === "login" && (
          <div className="flex flex-col gap-8">
            <div className="border border-border rounded-lg overflow-hidden">
              <div className="px-4 py-3 bg-muted">
                <label className="block text-[9px] tracking-[2px] text-muted-foreground/60 mb-1.5">EMAIL</label>
                <Input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  onKeyDown={(e) => e.key === "Enter" && sendCode()}
                  placeholder="you@example.com"
                  autoFocus
                  className="border-0 bg-transparent px-0 font-mono text-[13px] h-auto focus-visible:ring-0"
                />
              </div>
            </div>
            <Button
              onClick={sendCode}
              disabled={!email || isLoading}
              className="w-full h-11 text-xs tracking-[2px] font-mono"
            >
              {isLoading ? <div className="w-4 h-4 border-2 border-primary-foreground border-t-transparent rounded-full animate-spin" /> : "SEND CODE"}
            </Button>
            <div className="flex items-center justify-center gap-1.5">
              <span className="text-[10px] tracking-[1px] text-muted-foreground/60">NO ACCOUNT?</span>
              <button onClick={() => switchTo("signup")} className="text-[10px] tracking-[1px] text-foreground underline font-medium">CREATE ONE</button>
            </div>
          </div>
        )}

        {/* OTP */}
        {screen === "otp" && (
          <div className="flex flex-col gap-8 items-center">
            <div className="flex flex-col items-center gap-1">
              <span className="text-[10px] tracking-[1px] text-muted-foreground/60">CODE SENT TO</span>
              <span className="text-[11px] tracking-[0.5px] text-foreground font-medium">{email.toUpperCase()}</span>
            </div>
            <div className="flex gap-2">
              {otpDigits.map((digit, i) => (
                <div key={i} className="w-12 h-14 bg-muted border border-border flex items-center justify-center relative focus-within:border-foreground focus-within:border-2">
                  <span className="text-2xl font-medium text-foreground font-mono">{digit}</span>
                  <input
                    ref={(el) => { otpRefs.current[i] = el; }}
                    type="text"
                    inputMode="numeric"
                    maxLength={6}
                    value={digit}
                    onChange={(e) => handleOtpInput(e.target.value, i)}
                    onKeyDown={(e) => handleOtpKeyDown(e, i)}
                    className="absolute inset-0 w-full h-full opacity-[0.01] text-center text-2xl font-mono"
                  />
                </div>
              ))}
            </div>
            <Button
              onClick={() => verifyCode(otpCode)}
              disabled={otpCode.length !== 6 || isLoading}
              className="w-full h-11 text-xs tracking-[2px] font-mono"
            >
              {isLoading ? <div className="w-4 h-4 border-2 border-primary-foreground border-t-transparent rounded-full animate-spin" /> : "VERIFY"}
            </Button>
            <div className="flex gap-4">
              <button onClick={() => { setOtpDigits(Array(6).fill("")); sendCode(); }} className="text-[10px] tracking-[1px] text-muted-foreground">RESEND CODE</button>
              <button onClick={() => switchTo("login")} className="text-[10px] tracking-[1px] text-muted-foreground">CHANGE EMAIL</button>
            </div>
          </div>
        )}

        {/* Signup */}
        {screen === "signup" && (
          <div className="flex flex-col gap-8">
            <div className="border border-border rounded-lg overflow-hidden">
              <div className="px-4 py-3 bg-muted border-b border-border">
                <label className="block text-[9px] tracking-[2px] text-muted-foreground/60 mb-1.5">EMAIL</label>
                <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" autoFocus className="border-0 bg-transparent px-0 font-mono text-[13px] h-auto focus-visible:ring-0" />
              </div>
              <div className="px-4 py-3 bg-muted border-b border-border">
                <label className="block text-[9px] tracking-[2px] text-muted-foreground/60 mb-1.5">PASSWORD</label>
                <Input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="minimum 8 characters" className="border-0 bg-transparent px-0 font-mono text-[13px] h-auto focus-visible:ring-0" />
              </div>
              <div className="px-4 py-3 bg-muted">
                <label className="block text-[9px] tracking-[2px] text-muted-foreground/60 mb-1.5">CONFIRM PASSWORD</label>
                <Input type="password" value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} onKeyDown={(e) => e.key === "Enter" && createAccount()} placeholder="repeat password" className="border-0 bg-transparent px-0 font-mono text-[13px] h-auto focus-visible:ring-0" />
              </div>
            </div>
            {confirmPassword && password !== confirmPassword && (
              <span className="text-[10px] tracking-[1px] text-destructive text-center">PASSWORDS DO NOT MATCH</span>
            )}
            <Button onClick={createAccount} disabled={!signupValid || isLoading} className="w-full h-11 text-xs tracking-[2px] font-mono">
              {isLoading ? <div className="w-4 h-4 border-2 border-primary-foreground border-t-transparent rounded-full animate-spin" /> : "CREATE ACCOUNT"}
            </Button>
            <div className="flex items-center justify-center gap-1.5">
              <span className="text-[10px] tracking-[1px] text-muted-foreground/60">ALREADY HAVE AN ACCOUNT?</span>
              <button onClick={() => switchTo("login")} className="text-[10px] tracking-[1px] text-foreground underline font-medium">SIGN IN</button>
            </div>
          </div>
        )}

        {/* Error */}
        {errorMessage && (
          <p className="text-[10px] tracking-[0.5px] text-destructive text-center">{errorMessage}</p>
        )}
      </div>
    </div>
  );
}
