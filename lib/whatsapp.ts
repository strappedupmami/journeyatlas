import { CONTACT_WHATSAPP_MESSAGE } from "@/lib/site";

const DEFAULT_PHONE = "972500000000";

export function getWhatsAppLink(customMessage?: string): string {
  const number = process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ?? DEFAULT_PHONE;
  const message = encodeURIComponent(customMessage ?? CONTACT_WHATSAPP_MESSAGE);
  return `https://wa.me/${number}?text=${message}`;
}
