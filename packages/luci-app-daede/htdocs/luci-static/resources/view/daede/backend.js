// SPDX-License-Identifier: Apache-2.0

'use strict';
'require baseclass';
'require fs';
'require rpc';

const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

const BACKEND = {
	name: 'daed',
	label: 'daed',
	uci: 'daed',
	initd: '/etc/init.d/daed',
	log: '/var/log/daed/daed.log',
	pkg: 'daed',
	hasWebUI: true,
	useNetns: true,
	defaultListen: '0.0.0.0:2023'
};

function serviceStatus(name) {
	return L.resolveDefault(callServiceList(name), {}).then(function(svc) {
		let pid = 0, running = false;

		try {
			const inst = svc[name].instances[name];
			running = !!inst.running;
			pid = inst.pid || 0;
		} catch (e) {}

		return { running: running, pid: pid };
	});
}

function detectRunning() {
	return L.resolveDefault(fs.exec('/bin/pidof', ['daed']), { code: 1 }).then(function(res) {
		return { daed: !!res && res.code === 0 };
	});
}

function detectBackend() {
	return detectRunning().then(function(running) {
		return {
			name: 'daed',
			backend: BACKEND,
			installed: { daed: true },
			running: running
		};
	});
}

return baseclass.extend({
	BACKENDS: { daed: BACKEND },
	detectRunning: detectRunning,
	detectBackend: detectBackend,
	serviceStatus: serviceStatus
});
