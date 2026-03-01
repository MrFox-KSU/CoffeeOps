/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Supabase uses remote images sometimes; add domains later if needed.
  images: {
    remotePatterns: []
  }
};

export default nextConfig;
