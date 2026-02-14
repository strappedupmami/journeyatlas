type ProductCardProps = {
  title: string;
  description: string;
  bullets: string[];
  badge: string;
};

export function ProductCard({ title, description, bullets, badge }: ProductCardProps) {
  return (
    <article className="product-card">
      <p className="pill">{badge}</p>
      <h3>{title}</h3>
      <p>{description}</p>
      <ul>
        {bullets.map((bullet) => (
          <li key={bullet}>{bullet}</li>
        ))}
      </ul>
    </article>
  );
}
