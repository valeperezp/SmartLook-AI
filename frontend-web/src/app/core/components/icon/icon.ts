import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

export type IconName =
  | 'home'
  | 'users'
  | 'store'
  | 'truck'
  | 'shirt'
  | 'tag'
  | 'ruler'
  | 'palette'
  | 'calendar'
  | 'package'
  | 'grid'
  | 'check-circle'
  | 'alert-circle'
  | 'settings'
  | 'user'
  | 'sparkles'
  | 'focus'
  | 'menu'
  | 'chevron-left';

@Component({
  selector: 'app-icon',
  standalone: true,
  imports: [CommonModule],
  template: `
    <svg
      [attr.width]="size"
      [attr.height]="size"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      @switch (name) {
        @case ('home') {
          <path d="M4 11 12 4 20 11" />
          <path d="M6 10v9h5v-5h2v5h5v-9" />
        }
        @case ('users') {
          <circle cx="9" cy="8" r="3.2" />
          <path d="M3.5 20c0-3.6 2.5-6 5.5-6s5.5 2.4 5.5 6" />
          <circle cx="17" cy="9" r="2.3" />
          <path d="M14.8 20c.2-2.6 1.6-4.4 3.7-4.9" />
        }
        @case ('store') {
          <path d="M4 9 12 3 20 9" />
          <rect x="4" y="9" width="16" height="11" />
          <rect x="10" y="14" width="4" height="6" />
        }
        @case ('truck') {
          <rect x="1.5" y="8" width="12.5" height="8" />
          <path d="M14 11h4l3.2 3.1V16h-7.2z" />
          <circle cx="5.5" cy="18" r="1.7" />
          <circle cx="17.5" cy="18" r="1.7" />
        }
        @case ('shirt') {
          <path
            d="M8.2 3 3.5 6.8l2 3 2-1.2V20h9V8.6l2 1.2 2-3L15.8 3l-1.6 1.6a2.9 2.9 0 0 1-4.1 0Z"
          />
        }
        @case ('tag') {
          <path d="M11 3H4v7l10 10 7-7L11 3Z" />
          <circle cx="7.5" cy="7.5" r="1.1" />
        }
        @case ('ruler') {
          <rect x="2.5" y="9" width="19" height="6" rx="1" />
          <path d="M6.5 9v2.2M10.5 9v3M14.5 9v2.2M18.5 9v3" />
        }
        @case ('palette') {
          <path
            d="M12 3a9 9 0 1 0 .5 18c1.2 0 1.8-.9 1.8-1.8 0-.6-.3-1.1-.6-1.6-.3-.5-.1-1.1.5-1.2H16a4 4 0 0 0 4-4C20 6.6 16.5 3 12 3Z"
          />
          <circle cx="7.6" cy="10.6" r="1.1" />
          <circle cx="9.6" cy="7" r="1.1" />
          <circle cx="14" cy="6.6" r="1.1" />
        }
        @case ('calendar') {
          <rect x="3" y="5" width="18" height="16" rx="2" />
          <path d="M3 10h18M8 3v4M16 3v4" />
        }
        @case ('package') {
          <path d="M12 3 20 7v10l-8 4-8-4V7l8-4Z" />
          <path d="M4.2 7.2 12 11l7.8-3.8M12 11v10" />
        }
        @case ('grid') {
          <rect x="3" y="3" width="7.5" height="7.5" rx="1.2" />
          <rect x="13.5" y="3" width="7.5" height="7.5" rx="1.2" />
          <rect x="3" y="13.5" width="7.5" height="7.5" rx="1.2" />
          <rect x="13.5" y="13.5" width="7.5" height="7.5" rx="1.2" />
        }
        @case ('check-circle') {
          <circle cx="12" cy="12" r="9" />
          <path d="M8 12.3l2.6 2.6L16 9.3" />
        }
        @case ('alert-circle') {
          <circle cx="12" cy="12" r="9" />
          <path d="M12 7.5v5.5M12 16.2h.01" />
        }
        @case ('settings') {
          <line x1="4" y1="6" x2="20" y2="6" />
          <circle cx="14" cy="6" r="2" />
          <line x1="4" y1="12" x2="20" y2="12" />
          <circle cx="8" cy="12" r="2" />
          <line x1="4" y1="18" x2="20" y2="18" />
          <circle cx="16" cy="18" r="2" />
        }
        @case ('user') {
          <circle cx="12" cy="8" r="4" />
          <path d="M4.5 20c0-4.4 3.4-7 7.5-7s7.5 2.6 7.5 7" />
        }
        @case ('sparkles') {
          <path
            d="M11 3.2c.7 3 1.6 4.9 2.8 6.1s3 2 5.9 2.7c.4.1.4.7 0 .8-3 .7-4.8 1.5-5.9 2.7-1.2 1.2-2.1 3.1-2.8 6.1-.1.4-.7.4-.8 0-.7-3-1.6-4.9-2.8-6.1-1.1-1.2-2.9-2-5.9-2.7-.4-.1-.4-.7 0-.8 3-.7 4.8-1.5 5.9-2.7 1.2-1.2 2.1-3.1 2.8-6.1.1-.4.7-.4.8 0Z"
            fill="currentColor"
            stroke="none"
          />
          <path
            d="M18.3 3.5c.3 1.1.6 1.8 1.1 2.3.5.5 1.2.8 2.3 1.1.2 0 .2.3 0 .3-1.1.3-1.8.6-2.3 1.1-.5.5-.8 1.2-1.1 2.3 0 .2-.3.2-.3 0-.3-1.1-.6-1.8-1.1-2.3-.5-.5-1.2-.8-2.3-1.1-.2 0-.2-.3 0-.3 1.1-.3 1.8-.6 2.3-1.1.5-.5.8-1.2 1.1-2.3 0-.2.3-.2.3 0Z"
            fill="currentColor"
            stroke="none"
          />
        }
        @case ('focus') {
          <path d="M4 8V5a1 1 0 0 1 1-1h3" />
          <path d="M16 4h3a1 1 0 0 1 1 1v3" />
          <path d="M20 16v3a1 1 0 0 1-1 1h-3" />
          <path d="M8 20H5a1 1 0 0 1-1-1v-3" />
          <circle cx="12" cy="12" r="3" fill="currentColor" stroke="none" />
        }
        @case ('menu') {
          <line x1="4" y1="7" x2="20" y2="7" />
          <line x1="4" y1="12" x2="20" y2="12" />
          <line x1="4" y1="17" x2="20" y2="17" />
        }
        @case ('chevron-left') {
          <path d="M15 5 8 12l7 7" />
        }
      }
    </svg>
  `,
})
export class IconComponent {
  @Input() name!: IconName;
  @Input() size = 20;
}
