import type { Metadata } from 'next';
import 'bootstrap/dist/css/bootstrap.min.css';
import '../../styles/design.css';

export const metadata: Metadata = {
  title: 'CoffeeOps Executive BI',
  description: 'Production-grade executive BI for coffee operations (Supabase + Next.js)'
};

export default function RootLayout({
  children
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        {children}
      </body>
    </html>
  );
}
