const $ = (id) => document.getElementById(id);
const screen = $('screen');

const fmt = (s) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;

function show(d) {
    const dead = d.state === 'dead';
    const ready = dead && d.seconds <= 0;
    screen.classList.remove('hidden');
    screen.classList.toggle('dead', dead);
    screen.classList.toggle('ready', ready);

    $('icon').className = dead ? 'fa-solid fa-skull' : 'fa-solid fa-heart-crack';
    $('eyebrow').textContent = dead ? 'YOU ARE' : 'YOU ARE';
    $('title').textContent = dead ? 'UNCONSCIOUS' : 'DOWN';
    $('cause').textContent = d.cause && d.cause !== 'Unknown' ? d.cause : '';

    $('timer-label').textContent = ready ? 'You can respawn' : dead ? 'Respawn available in' : 'Bleeding out in';
    $('time').textContent = ready ? 'Now' : fmt(d.seconds);
    $('fill').style.width = `${ready ? 100 : Math.max(0, Math.min(100, (d.seconds / d.total) * 100))}%`;

    $('key-respawn').classList.toggle('hidden', !ready);
    $('key-respawn').querySelector('span').textContent = `Hold ${d.holdTime}s to respawn`;
}

window.addEventListener('message', ({ data }) => {
    switch (data.action) {
        case 'show': show(data.data); break;
        case 'hide': screen.classList.add('hidden'); $('hold').style.width = '0'; break;
        case 'hold': $('hold').style.width = `${data.data * 100}%`; break;
    }
});
