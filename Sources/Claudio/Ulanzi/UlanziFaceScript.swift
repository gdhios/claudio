/// Claudio's face on an Ulanzi TC001 under AWTRIX NG: a Berry script that
/// runs on the clock itself, about forty frames a second. It draws the head
/// and keeps the eyes alive (the pupil wanders and blinks, the antenna
/// breathes) while Claudio only sets its `gaze` from the Mac.
///
/// What the device should hold, byte for byte: Claudio compares the source
/// the device hands back with this one and installs it again on the smallest
/// difference, trailing newline included. Raise `@version` with every change.
enum UlanziFaceScript {
    /// The script's `@name`, which is also its app name in every path.
    static let appName = "Claudio"

    static let source = """
        # @name    Claudio
        # @desc    Claudio's face while he works on the Mac. The gaze is set by Claudio, the eyes live here.
        # @author  Okonoma
        # @version 1.0
        # @config  gaze   select "Gaze"   default=off options=off,repos,veille,fait,vide help="Set by Claudio on the Mac. off hides the face."
        # @config  ink    color  "Ink"    default=#B0B0B0 help="Head ring, antenna and mustache"
        # @config  hollow color  "Hollow" default=#31104F help="Inside the head, and the pupils"

        import math

        class Claudio
          var gaze, ink, hollow
          var x            # left column of the head (12 wide)
          var px, py       # pupil offset inside the eye, 0..2 each
          var move_at      # now_ms() of the next pupil move
          var blink_at     # now_ms() when the next blink starts
          var shown, held

          def init()
            self.gaze = store.get("gaze")
            self.ink = store.get("ink")
            self.hollow = store.get("hollow")
            self.x = (width() - 12) / 2
            self.px = 1
            self.py = 1
            var t = now_ms()
            self.move_at = t + 1200
            self.blink_at = t + 2500
            self.shown = false
            self.held = false
          end

          # Nothing to say while Claudio rests: the rotation passes by.
          def should_show()
            return self.gaze != "off"
          end

          # Once summoned, stay until Claudio says off; the pause below is the belt, this is the braces.
          def duration()
            return self.gaze == "off" ? 0 : 1800000
          end

          def on_show()
            self.shown = true
          end

          def on_hide()
            self.shown = false
            if self.held
              rotation.resume()
              self.held = false
            end
          end

          # An API move clears a pause; put it back once a second while the face is up.
          def loop()
            if self.shown && self.gaze != "off"
              rotation.pause()
              self.held = true
            end
          end

          # A colour scaled by f in 0.0..1.0, channel by channel.
          def dim(c, f)
            return rgb(int(((c >> 16) & 255) * f), int(((c >> 8) & 255) * f), int((c & 255) * f))
          end

          def eyes(t)
            var l = self.x + 2
            var r = self.x + 7
            var g = self.gaze
            if g == "repos"
              if t >= self.blink_at + 110
                self.blink_at = t + 2500 + math.rand() % 3500
              end
              if t >= self.blink_at
                g = "veille"   # a blink is a short sleep
              elif t >= self.move_at
                self.px = math.rand() % 3
                self.py = math.rand() % 3
                self.move_at = t + 700 + math.rand() % 2600
              end
            end
            if g == "repos"
              rect_fill(l, 2, 3, 3, 0xFFFFFF)
              rect_fill(r, 2, 3, 3, 0xFFFFFF)
              pixel(l + self.px, 2 + self.py, self.hollow)
              pixel(r + self.px, 2 + self.py, self.hollow)
            elif g == "veille"
              rect_fill(l, 3, 3, 1, 0xFFFFFF)
              rect_fill(r, 3, 3, 1, 0xFFFFFF)
            elif g == "fait"
              pixel(l, 3, 0xFFFFFF)
              pixel(l + 1, 2, 0xFFFFFF)
              pixel(l + 2, 3, 0xFFFFFF)
              pixel(r, 3, 0xFFFFFF)
              pixel(r + 1, 2, 0xFFFFFF)
              pixel(r + 2, 3, 0xFFFFFF)
            else
              rect_fill(l, 2, 3, 3, 0xFFFFFF)
              rect_fill(r, 2, 3, 3, 0xFFFFFF)
            end
          end

          def draw()
            if self.gaze == "off"
              rotation.resume()
              self.held = false
              rotation.next()
              return
            end
            var t = now_ms()
            var x = self.x
            clear()
            # Antenna ball; it breathes while he focuses.
            var ball = self.ink
            if self.gaze == "veille"
              var p = (t % 1400) / 700.0
              if p > 1.0 p = 2.0 - p end
              ball = self.dim(self.ink, 0.25 + 0.75 * p)
            end
            rect_fill(x + 5, 0, 2, 1, ball)
            # Head: the ring and its hollow.
            rect(x, 1, 12, 6, self.ink)
            rect_fill(x + 1, 2, 10, 4, self.hollow)
            self.eyes(t)
            # Mustache, wider than the head, covering its bottom edge.
            rect_fill(x - 2, 6, 16, 1, self.ink)
            rect_fill(x - 3, 7, 3, 1, self.ink)
            rect_fill(x + 12, 7, 3, 1, self.ink)
          end
        end

        return Claudio()

        """
}
