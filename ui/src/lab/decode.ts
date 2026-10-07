/**
 * Decoding for the test bench (2.0.0-player.36): a picked file into the song's source rate, and the deck's
 * windows again for the replay - by decodeAudioData on an OfflineAudioContext at the rate asked, the very
 * decoder (and resampler) the deck's own context uses, so a window decoded here is the window the voice
 * had. An OfflineAudioContext plays nothing, needs no tap and no secure page.
 */

type Offline = new (channels: number, length: number, rate: number) => OfflineAudioContext

/** `bytes` decoded at `rate`: every channel, as floats. */
export function decodeAt(bytes: ArrayBuffer, rate: number): Promise<Float32Array[]> {
  const scope = globalThis as { OfflineAudioContext?: Offline; webkitOfflineAudioContext?: Offline }
  const Decoder = scope.OfflineAudioContext ?? scope.webkitOfflineAudioContext
  if (!Decoder) return Promise.reject(new Error('this browser has no OfflineAudioContext to decode with'))
  const context = new Decoder(1, 1, rate)
  return new Promise((resolve, reject) => {
    const done = (buffer: AudioBuffer) => {
      const channels: Float32Array[] = []
      for (let c = 0; c < buffer.numberOfChannels; c++) channels.push(buffer.getChannelData(c).slice())
      resolve(channels)
    }
    try {
      //? the callback form, as the deck's: older WebKit has no promise from it
      const promise = context.decodeAudioData(bytes, done, (error) => reject(error ?? new Error('it could not be decoded'))) as Promise<AudioBuffer> | undefined
      promise?.catch?.(() => undefined)
    } catch (error) {
      reject(error)
    }
  })
}
