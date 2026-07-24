// GENERATED from the apps' menu definitions — do not hand-edit.
// Source: apps/native-macos/Sources/ImageKid/App.swift
//         apps/native-macos/Sources/FekthorTrace/FekthorApp.swift
// Regenerate whenever a .keyboardShortcut changes, so the docs cannot drift
// from what the apps actually bind.

export interface Shortcut { label: string; keys: string }
export interface ShortcutSection { title: string; items: Shortcut[] }

export const shortcuts: Record<string, ShortcutSection[]> = {
  "ImageKid": [
    {
      "title": "File",
      "items": [
        {
          "label": "New…",
          "keys": "⌘N"
        },
        {
          "label": "Open…",
          "keys": "⌘O"
        },
        {
          "label": "Close Image",
          "keys": "⌘W"
        },
        {
          "label": "Save",
          "keys": "⌘S"
        },
        {
          "label": "Save As…",
          "keys": "⇧⌘S"
        },
        {
          "label": "Save All",
          "keys": "⌥⌘S"
        }
      ]
    },
    {
      "title": "Edit",
      "items": [
        {
          "label": "Undo",
          "keys": "⌘Z"
        },
        {
          "label": "Redo",
          "keys": "⇧⌘Z"
        },
        {
          "label": "Cut",
          "keys": "⌘X"
        },
        {
          "label": "Copy",
          "keys": "⌘C"
        },
        {
          "label": "Paste",
          "keys": "⌘V"
        },
        {
          "label": "Delete",
          "keys": "⌘⌫"
        },
        {
          "label": "Duplicate",
          "keys": "⌘D"
        },
        {
          "label": "Select All",
          "keys": "⌘A"
        },
        {
          "label": "Invert Mask",
          "keys": "⌘I"
        }
      ]
    },
    {
      "title": "Image",
      "items": [
        {
          "label": "Canvas Size…",
          "keys": "⌥⌘C"
        },
        {
          "label": "Rotate 90° Clockwise",
          "keys": "⌘R"
        },
        {
          "label": "Rotate 90° Counterclockwise",
          "keys": "⇧⌘R"
        }
      ]
    },
    {
      "title": "Arrange",
      "items": [
        {
          "label": "Bring to Front",
          "keys": "⇧⌘]"
        },
        {
          "label": "Bring Forward",
          "keys": "⌘]"
        },
        {
          "label": "Send Backward",
          "keys": "⌘["
        },
        {
          "label": "Send to Back",
          "keys": "⇧⌘["
        }
      ]
    },
    {
      "title": "View",
      "items": [
        {
          "label": "Zoom In",
          "keys": "⌘+"
        },
        {
          "label": "Zoom Out",
          "keys": "⌘-"
        },
        {
          "label": "Actual Size (100%)",
          "keys": "⌘0"
        },
        {
          "label": "Fit to Window",
          "keys": "⇧⌘0"
        },
        {
          "label": "Show Files Sheet",
          "keys": "⌥⌘1"
        },
        {
          "label": "Hide",
          "keys": "⌘'"
        },
        {
          "label": "Disable",
          "keys": "⇧⌘'"
        }
      ]
    },
    {
      "title": "Tools",
      "items": [
        {
          "label": "Cancel Current Tool",
          "keys": "⎋"
        }
      ]
    }
  ],
  "Fekthor": [
    {
      "title": "File",
      "items": [
        {
          "label": "New Icon",
          "keys": "⌘N"
        },
        {
          "label": "Open…",
          "keys": "⌘O"
        },
        {
          "label": "Open Workspace…",
          "keys": "⇧⌘O"
        },
        {
          "label": "Save",
          "keys": "⌘S"
        },
        {
          "label": "Save As…",
          "keys": "⇧⌘S"
        },
        {
          "label": "Trace Image…",
          "keys": "⇧⌘T"
        }
      ]
    },
    {
      "title": "Edit",
      "items": [
        {
          "label": "Select All",
          "keys": "⌘A"
        },
        {
          "label": "Group",
          "keys": "⌘G"
        },
        {
          "label": "Ungroup",
          "keys": "⇧⌘G"
        }
      ]
    },
    {
      "title": "Arrange",
      "items": [
        {
          "label": "Bring to Front",
          "keys": "⌥⌘]"
        },
        {
          "label": "Bring Forward",
          "keys": "⌘]"
        },
        {
          "label": "Send Backward",
          "keys": "⌘["
        },
        {
          "label": "Send to Back",
          "keys": "⌥⌘["
        }
      ]
    },
    {
      "title": "View",
      "items": [
        {
          "label": "Snap to Points",
          "keys": "⌥⌘'"
        },
        {
          "label": "Preview Composed Icons",
          "keys": "⌥⌘P"
        },
        {
          "label": "Show Timeline",
          "keys": "⌥⌘T"
        }
      ]
    },
    {
      "title": "Workspace",
      "items": [
        {
          "label": "Workspace Settings…",
          "keys": "⇧⌘,"
        },
        {
          "label": "Export Profiles…",
          "keys": "⇧⌘E"
        },
        {
          "label": "Style Tokens…",
          "keys": "⇧⌘K"
        },
        {
          "label": "Animations…",
          "keys": "⌥⌘K"
        }
      ]
    }
  ]
};
