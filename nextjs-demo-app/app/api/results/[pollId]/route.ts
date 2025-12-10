import { NextResponse } from "next/server";

const resultsApiUrl = process.env.NEXT_PUBLIC_RESULTS_API_URL;

export async function GET(
  _request: Request,
  { params }: { params: { pollId: string } },
) {
  if (!resultsApiUrl) {
    return NextResponse.json(
      { error: "Results API URL not configured" },
      { status: 500 },
    );
  }

  const pollId = params.pollId;

  try {
    const res = await fetch(`${resultsApiUrl}/results?pollId=${encodeURIComponent(pollId)}`);

    if (!res.ok) {
      const text = await res.text().catch(() => "");
      console.error("Results API error:", res.status, text);
      return NextResponse.json(
        { error: "Upstream results API error" },
        { status: 502 },
      );
    }

    const data = await res.json();
    // Expecting shape like: { pollId, items: [{ option: "A", label: "API Gateway", count: 10 }, ...] }
    return NextResponse.json(data);
  } catch (err) {
    console.error("Results API network error:", err);
    return NextResponse.json(
      { error: "Network error calling results API" },
      { status: 500 },
    );
  }
}