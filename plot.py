import numpy as np
import matplotlib
import matplotlib.pyplot as plt
import scipy
import scipy.signal as sig

inp = ["samp0.txt", "samp1.txt", "samp2.txt"]
inp = ["samp0.txt", "samp2.txt"]

fig, ax = plt.subplots(3)
for i, fn in enumerate(inp):
    x = np.loadtxt(fn, delimiter=",")

    x = x[32:, :]
    x = x[0:1024*32, :]

    s = np.fft.fft(x, axis=0)
    s = 10 * np.log10(np.abs(s))

    s = np.fft.fftshift(s, axes=0)

    if True:
        ax[i].plot(s)
    else:
        ax[i].plot(x[0:100,0])
        ax[i].plot(x[0:100,1])

plt.show()




# arms = 32
# b = sig.fir_filter_design.firwin(32*arms, 0.25/arms, fs=1.0)

# np.savetxt("taps.txt", b)

# for i in range(16):
#     (w,h) = sig.freqz(b[i::32], fs=2)

#     #plt.plot(b[i::32])
#     #plt.plot(w, h)
#     plt.plot(w, np.abs(h))
# plt.show()