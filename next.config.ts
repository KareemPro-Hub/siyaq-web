import type { NextConfig } from "next";
const config: NextConfig = {
  poweredByHeader: false,
  devIndicators: false,
  outputFileTracingIncludes: {"/*": ["./data/quran.json", "./data/tafsir.json", "./data/provenance.json", "./data/source-policy.json"]},
  async headers() {
    return [{source: "/:path*", headers: [
      {key: "X-Content-Type-Options", value: "nosniff"},
      {key: "Referrer-Policy", value: "strict-origin-when-cross-origin"},
      {key: "Permissions-Policy", value: "camera=(), microphone=(self), geolocation=()"}
    ]}];
  }
};
export default config;
