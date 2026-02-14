import { getWhatsAppLink } from "@/lib/whatsapp";

type WhatsAppButtonProps = {
  text?: string;
  className?: string;
};

export function WhatsAppButton({ text = "לדבר איתנו ב-WhatsApp", className }: WhatsAppButtonProps) {
  return (
    <a
      href={getWhatsAppLink()}
      target="_blank"
      rel="noopener noreferrer"
      className={className ? `btn btn-primary ${className}` : "btn btn-primary"}
    >
      {text}
    </a>
  );
}
