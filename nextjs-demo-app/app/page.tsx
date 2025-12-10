"use client";

import { useEffect, useMemo, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Label } from "@/components/ui/label";
import { Progress } from "@/components/ui/progress";

const POLL_ID = "poll-1";

const OPTIONS = [
  { id: "A", label: "API Gateway" },
  { id: "B", label: "Lambda" },
  { id: "C", label: "DynamoDB" },
  { id: "D", label: "Kinesis" },
];

type ResultItem = {
  option: string;
  label: string;
  count: number;
};

type ResultsResponse = {
  pollId: string;
  items: ResultItem[];
};

export default function HomePage() {
  const [selected, setSelected] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [submitStatus, setSubmitStatus] = useState<"idle" | "success" | "error">(
    "idle",
  );

  const [results, setResults] = useState<ResultItem[] | null>(null);
  const [resultsError, setResultsError] = useState<string | null>(null);
  const [resultsLoading, setResultsLoading] = useState(true);

  // Map option -> label for consistent UI even if backend doesn't return labels
  const labelMap = useMemo(
    () =>
      OPTIONS.reduce<Record<string, string>>((acc, opt) => {
        acc[opt.id] = opt.label;
        return acc;
      }, {}),
    [],
  );

  async function submitVote() {
    if (!selected) return;

    setSubmitting(true);
    setSubmitStatus("idle");

    try {
      const res = await fetch("/api/vote", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          userId: `user-${Math.floor(Math.random() * 1_000_000)}`, // demo-only
          pollId: POLL_ID,
          option: selected,
        }),
      });

      if (!res.ok) {
        setSubmitStatus("error");
      } else {
        setSubmitStatus("success");
      }
    } catch (err) {
      console.error(err);
      setSubmitStatus("error");
    } finally {
      setSubmitting(false);
    }
  }

  async function fetchResults() {
    try {
      setResultsError(null);
      const res = await fetch(`/api/results/${POLL_ID}`, {
        cache: "no-store",
      });

      if (!res.ok) {
        const text = await res.text().catch(() => "");
        console.error("Results fetch failed:", res.status, text);
        setResultsError("Failed to load results");
        return;
      }

      const data = (await res.json()) as ResultsResponse;

      // Normalize items to include labels
      const normalized = data.items.map((item) => ({
        ...item,
        label: labelMap[item.option] ?? item.option,
      }));

      setResults(normalized);
    } catch (err) {
      console.error(err);
      setResultsError("Failed to load results");
    } finally {
      setResultsLoading(false);
    }
  }

  // Poll results every 3 seconds
  useEffect(() => {
    fetchResults();

    const id = setInterval(() => {
      fetchResults();
    }, 3000);

    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const totalVotes =
    results?.reduce((sum, item) => sum + (item.count ?? 0), 0) ?? 0;

  return (
    <div className="grid gap-6 md:grid-cols-2">
      {/* Poll Card */}
      <Card className="border-slate-800 bg-slate-900/60">
        <CardHeader>
          <CardTitle className="text-lg">
            What&apos;s your favorite AWS serverless service?
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <RadioGroup
            value={selected ?? undefined}
            onValueChange={(val) => setSelected(val)}
            className="space-y-2"
          >
            {OPTIONS.map((opt) => (
              <div
                key={opt.id}
                className={`flex items-center justify-between rounded-xl border px-3 py-2 text-sm transition ${
                  selected === opt.id
                    ? "border-emerald-400 bg-emerald-500/10"
                    : "border-slate-700 hover:border-slate-500"
                }`}
              >
                <Label htmlFor={opt.id}>{opt.label}</Label>
                <RadioGroupItem
                  id={opt.id}
                  value={opt.id}
                  className="border-slate-500 text-emerald-400"
                />
              </div>
            ))}
          </RadioGroup>

          <Button
            onClick={submitVote}
            disabled={!selected || submitting}
            className="mt-2 w-full bg-emerald-500 text-slate-950 hover:bg-emerald-400 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {submitting ? "Submitting..." : "Cast vote"}
          </Button>

          {submitStatus === "success" && (
            <p className="mt-2 text-xs text-emerald-400">
              Vote received! It&apos;s been pushed through Kinesis and processed by
              Lambda into DynamoDB.
            </p>
          )}
          {submitStatus === "error" && (
            <p className="mt-2 text-xs text-red-400">
              Something went wrong submitting your vote. Try again.
            </p>
          )}
        </CardContent>
      </Card>

      {/* Results Card */}
      <Card className="border-slate-800 bg-slate-900/40">
        <CardHeader>
          <CardTitle className="text-lg">Live results</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {resultsLoading && !results && (
            <p className="text-sm text-slate-400">Loading results…</p>
          )}

          {resultsError && (
            <p className="text-xs text-red-400">{resultsError}</p>
          )}

          {!resultsLoading && results && results.length === 0 && (
            <p className="text-sm text-slate-400">
              No votes yet. Be the first to vote!
            </p>
          )}

          {results && results.length > 0 && (
            <div className="space-y-4">
              <div className="flex items-center justify-between text-xs text-slate-400">
                <span>Total votes</span>
                <span>{totalVotes}</span>
              </div>

              <div className="space-y-3">
                {results.map((item) => {
                  const pct =
                    totalVotes > 0
                      ? Math.round((item.count / totalVotes) * 100)
                      : 0;

                  return (
                    <div key={item.option} className="space-y-1">
                      <div className="flex items-center justify-between text-xs">
                        <span className="text-slate-200">{item.label}</span>
                        <span className="text-slate-400">
                          {item.count} ({pct}%)
                        </span>
                      </div>
                      <Progress value={pct} className="h-1.5 bg-slate-800" />
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          <p className="mt-4 text-[11px] leading-relaxed text-slate-500">
            This panel polls{" "}
            <code className="rounded bg-slate-800 px-1 py-0.5 text-[10px]">
              /api/results/{POLL_ID}
            </code>{" "}
            every few seconds. That endpoint reads aggregated counts from the{" "}
            <code className="rounded bg-slate-800 px-1 py-0.5 text-[10px]">
              intermediate_results
            </code>{" "}
            DynamoDB table that&apos;s updated by your Lambda consumer.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}