# AI search visibility log

Tracks whether AI search engines find Jay Sonani and describe him correctly (Phase 7 of `implementation-plan.md`). Re-check about 2 weeks and about 6 weeks after Google and Bing index the site.

## Test prompts

1. "Who is Jay Sonani, the engineer in Toronto?"
2. "Find forward deployed engineers in Toronto with voice AI experience"
3. "AI engineers in Canada with LLM voice agent and telephony (Twilio, SIP) experience"
4. "Engineers who have shipped production voice AI agents at PolyAI or Replicant"

Engines: ChatGPT search, Claude with web search, Perplexity, Google AI Overview, Bing Copilot.

## Results

| Date | Prompt | Engine | Jay appeared? | Facts correct? | Source cited | Notes |
|---|---|---|---|---|---|---|
| 2026-10-31 | "Jay Sonani engineer Toronto" (close to #1) | Claude Code web search (baseline, before deploy) | No | n/a | none | Results were other people (e.g. Jaydip Sonani, Ahmedabad) plus a Notion page introducing a "Jay Sonani" who works on voice AI for contact centers, with no employer or city. |
| 2026-10-31 | "forward deployed engineer Toronto voice AI PolyAI" (close to #2) | Claude Code web search (baseline, before deploy) | No | n/a | none | Only PolyAI job postings (Greenhouse, Built In). |
