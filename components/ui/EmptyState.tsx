"use client";

export function EmptyState({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="card">
      <div className="card-body">
        <div className="h5 mb-1">{title}</div>
        {description && <div className="text-secondary mb-3">{description}</div>}
        {action}
      </div>
    </div>
  );
}
