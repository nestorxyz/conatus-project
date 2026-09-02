# `Hey Conatus` collection and consent packet

**Status:** Review-ready engineering draft for M2-02b2b1. It is not legal
advice and does not authorize recording. A qualified privacy review, an actual
withdrawal contact, operator approval, and each participant's explicit consent
are required before M2-02b2b2 records or imports a voice.

The collection design follows four conservative rules: consent must be a clear
affirmative choice, its purposes must be specific, only necessary data should
be collected, and raw recordings need a justified deletion schedule. These are
engineering safeguards, not a claim that one document satisfies every launch
jurisdiction.

- <https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/lawful-basis/consent/what-is-valid-consent/>
- <https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/data-protection-principles/a-guide-to-the-data-protection-principles/data-minimisation/>
- <https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/data-protection-principles/a-guide-to-the-data-protection-principles/storage-limitation/>

## Participant-facing consent draft

> Conatus is asking you to contribute short voice recordings and non-wake
> background audio to train and evaluate the local “Hey Conatus” wake detector.
> Participation is optional. Refusing or withdrawing will not affect your
> access to Conatus or any compensation already earned.
>
> If you agree, Conatus may use your accepted recordings to train and evaluate
> wake models and may distribute resulting model weights in the open-source and
> commercial Conatus product. Conatus will not publish your raw recordings or
> use them to identify or imitate you. A derived model cannot reliably be
> untrained after release, so the withdrawal procedure and model-release cutoff
> shown with this request matter: a valid request received before that cutoff
> deletes your raw recordings and excludes them from unreleased candidates;
> after release, Conatus can delete retained raw recordings but may be unable to
> remove their influence from an already distributed model.
>
> The session uses an opaque participant code instead of your name or account
> ID. Do not record another person. You can stop, discard a take, or leave at
> any time. By affirming, you confirm that you are at least 18, understand the
> stated purposes and withdrawal limit, are speaking in a private setting
> without third-party voices, and separately allow training, evaluation, and
> distribution of derived model weights.

The production consent screen must show, rather than hide in terms:

- the controller/operator identity and real contact route;
- what audio is requested and the exact three permitted uses;
- where raw audio is stored, who can access it, and any international transfer;
- compensation, if any, without making already-earned compensation conditional;
- the raw-audio deletion date and the candidate-release withdrawal cutoff;
- a separate affirmative control for every permitted use, all initially off;
- an equally visible decline action and a durable receipt available to the participant.

## Operator gate before each session

1. Confirm the approved consent version, privacy review, withdrawal route,
   raw-audio deletion date, and candidate-release cutoff are current.
2. Create opaque participant, source, session, consent, and approval references
   outside Git. Never place names, email addresses, account IDs, signatures, or
   consent documents in the dataset manifest.
3. Verify the participant is an adult, is freely participating, understands all
   three uses, and can withdraw without losing already-earned compensation.
4. Ask the participant to use a private room. Stop and delete the temporary take
   if another person's voice, private conversation, or identifying speech enters it.
5. Validate the strict `conatus-wake-consent-v1` receipt, including its opaque
   controller reference, raw-audio deletion date, and model-release cutoff,
   before any recorder backend may start. A receipt is evidence of the operator
   flow, not proof by itself.
6. Record one prompted take at a time. Keep it temporary until the participant
   reviews it; either retain the accepted take or delete the rejected take.
7. Verify 16 kHz mono metadata and SHA-256 evidence, then create the external
   M2-02b2a dataset manifest. Never commit audio or consent records.

## Initial Mac V1 corpus gate

These are product-defined minimums for the first candidate, not universal
industry standards and not a substitute for M2-02b2c live testing.

| Evidence | Candidate gate |
| --- | --- |
| Adults | 48 distinct consented speakers: at least 24 train, 12 validation, and 12 test; no speaker or recording session crosses a split |
| Wake examples | At least 20 accepted `Hey Conatus` takes per speaker, balanced across quiet/ordinary-room conditions, 0.5–3 m distance, natural pace, and same-sentence continuation |
| Pronunciation scope | Every split contains at least 4 speakers tagged `es-PE` and 4 tagged `en-US`; tags describe tested pronunciation groups, not support for all speakers of a language |
| Negative examples | At least 24 hours held out for testing, including ordinary room noise, media, conversation that participants are authorized to record, and confusable phrases; no incidental third-party recording |
| Offline candidate | Zero false accepts in the held-out 24 hours and no more than 5% false rejects overall or within either declared pronunciation group |
| Provenance | Every clip passes M2-02b2a, every source is consented and commercially distributable, and the candidate/runtime manifest digests match exact bytes |

A failed subgroup or aggregate threshold blocks the candidate. Passing does not
claim production readiness: supported-Mac false-wake hours, same-sentence
latency, sleep/wake, microphone permission, headset and route-change recovery,
and real household conditions remain M2-02b2c.

## Code boundary delivered by M2-02b2b1

`ConatusWakeCollection` is a pure consent and state-machine library. It:

- strictly validates the opaque consent receipt and all three permitted uses;
- cannot begin a planned take before validated consent;
- represents start, immediate stop/delete, review, accept, and discard as
  directives for a future recorder;
- validates only safe audio evidence and exposes public counts/status without
  participant, consent, path, prompt, or audio data;
- imports no microphone, recorder, Apple Speech, network, filesystem-write, or
  model-training API.

M2-02b2b1 deliberately provides no recorder backend and must not be used as a
pretext to collect data. M2-02b2b2 owns the reviewed recorder/import operation,
the consented external corpus, and the candidate training run.
