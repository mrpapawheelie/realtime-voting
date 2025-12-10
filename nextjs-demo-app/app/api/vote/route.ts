import { NextResponse } from "next/server";

const voteApiUrl = process.env.NEXT_PUBLIC_VOTE_API_URL;

export async function POST(request: Request) {
  if (!voteApiUrl) {
    return NextResponse.json(
      { error: "Vote API URL not configured" },
      { status: 500 },
    );
  }

  const body = await request.json();

  try {
    const res = await fetch(`${voteApiUrl}/vote`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const text = await res.text().catch(() => "");
      console.error("Vote API error:", res.status, text);
      return NextResponse.json(
        { error: "Upstream vote API error" },
        { status: 502 },
      );
    }

    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("Vote API network error:", err);
    return NextResponse.json(
      { error: "Network error calling vote API" },
      { status: 500 },
    );
  }
}