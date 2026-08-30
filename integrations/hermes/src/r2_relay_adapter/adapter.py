"""Minimal Hermes BasePlatformAdapter implementation for the R2 relay."""

from __future__ import annotations

import asyncio
import logging
import mimetypes
import os
import time
from pathlib import Path
from typing import Any, Dict, Optional

from importlib.metadata import PackageNotFoundError, version

from gateway.config import Platform, PlatformConfig
from gateway.platforms.base import BasePlatformAdapter, MessageEvent, MessageType, SendResult

from .address_mapping import build_source_chat_id, new_stream_id, parse_relay_target
from .checkpoint_store import FileCheckpointStore
from .client import R2RelayClient
from .config import resolve_r2_relay_env_config
from .inbound_mapping import format_inbound_text, infer_message_type
from .outbound_mapping import build_send_options
from .service import IDENTITY_REFRESH_INTERVAL_MS
from .service_factory import build_relay_service
from .install_manifest import PLATFORM_NAME


try:
    PACKAGE_VERSION = version('r2-relay-adapter')
except PackageNotFoundError:  # pragma: no cover - local editable/uninstalled checkout
    PACKAGE_VERSION = '0.1.0'


logger = logging.getLogger(__name__)


def check_r2_relay_requirements() -> bool:
    cfg = resolve_r2_relay_env_config({})
    return cfg.configured


def _resolve_hermes_home() -> Path:
    configured = os.getenv('HERMES_HOME', '').strip()
    if configured:
        return Path(configured).expanduser()
    return Path.home() / '.hermes'


def _identity_models_payload(config: Any) -> dict[str, Any] | None:
    available_models = [dict(entry) for entry in getattr(config, 'available_models', ()) if entry.get('id')]
    default_model = getattr(config, 'default_model', None)
    if default_model and not any(entry.get('id') == default_model for entry in available_models):
        provider = default_model.split('/', 1)[0] if '/' in default_model else None
        available_models.insert(0, {'id': default_model, 'label': None, 'provider': provider or None})
    if not available_models and not default_model:
        return None
    return {
        'available': available_models,
        'default': default_model,
    }


class R2RelayAdapter(BasePlatformAdapter):
    def __init__(
        self,
        config: PlatformConfig,
        client: Optional[Any] = None,
        service: Optional[Any] = None,
        checkpoint_store: Optional[Any] = None,
    ):
        super().__init__(config, Platform(PLATFORM_NAME))
        self._relay_config = resolve_r2_relay_env_config(config.extra or {})
        self._client = client
        self._service = service
        self._default_checkpoint_path = _resolve_hermes_home() / 'r2-relay-adapter' / 'checkpoint.json'
        self._checkpoint_store = checkpoint_store or FileCheckpointStore(self._default_checkpoint_path)
        self._poll_task: asyncio.Task | None = None
        self._identity_heartbeat_task: asyncio.Task | None = None
        self._abort_event = asyncio.Event()
        self._stream_sessions: dict[str, dict[str, Any]] = {}

    @property
    def name(self) -> str:
        return "R2 Relay"

    @property
    def relay_config(self):
        return self._relay_config

    @property
    def default_checkpoint_path(self) -> Path:
        return self._default_checkpoint_path

    @property
    def checkpoint_store(self):
        return self._checkpoint_store

    @property
    def client(self):
        if self._client is None and self._relay_config.configured:
            self._client = R2RelayClient.from_env_config(self._relay_config)
        return self._client

    @property
    def service(self):
        if self._service is None and self._relay_config.configured:
            self._service = build_relay_service(
                config=self._relay_config,
                client=self.client,
                checkpoint_store=self._checkpoint_store,
            )
        return self._service

    def _identity_payload(self) -> dict[str, Any]:
        models = _identity_models_payload(self._relay_config)
        agent: dict[str, Any] = {
            'id': 'main',
            'display_name': 'Hermes',
            'description': None,
            'is_default': True,
            'models': models,
            'default_route': {'agent_id': 'main'},
        }
        conversation: dict[str, Any] = {
            'id': self._relay_config.discovery_conversation_id,
            'display_title': (
                self._relay_config.discovery_conversation_title
                or self._relay_config.discovery_conversation_id
            ),
            'route': {
                'agent_id': 'main',
                'conversation_id': self._relay_config.discovery_conversation_id,
                'instance_id': self._relay_config.discovery_thread_id or None,
            },
            'source': {
                'channel': 'hermes',
                'chat_kind': 'dm',
            },
            'updated_at': None,
        }
        limits: dict[str, Any] | None = None
        if self._relay_config.inbound_attachment_max_bytes or self._relay_config.oversize_attachment_behavior:
            limits = {
                'inbound_attachment_max_bytes': self._relay_config.inbound_attachment_max_bytes,
                'oversize_attachment_behavior': self._relay_config.oversize_attachment_behavior,
            }
        return {
            'peer': self._relay_config.server_id,
            'display_name': self._relay_config.display_name,
            'role': 'server',
            'protocol': {'name': 'r2-relay', 'version': 3},
            'software': {'id': 'hermes', 'name': 'Hermes', 'version': PACKAGE_VERSION},
            'capabilities': {
                'messaging': {'text': True, 'streaming': True, 'reactions': False, 'system_events': False},
                'conversations': {'list': True, 'create': False, 'reset': False, 'archive': False, 'threading': True},
                'agents': {'list': True, 'multiple': False, 'switch': False, 'per_agent_models': bool(models)},
            },
            'agents': [agent],
            'conversations': [conversation],
            'limits': limits,
        }

    async def _publish_identity(self) -> None:
        await self.service.publish_identity(self._identity_payload())

    async def connect(self, *, is_reconnect: bool = False) -> bool:
        del is_reconnect
        if not self._relay_config.enabled:
            logger.info('r2 relay adapter disabled via config server_id=%s', self._relay_config.server_id)
            return False
        if not self._relay_config.configured:
            self._set_fatal_error(
                'MISSING_CREDENTIALS',
                'R2_RELAY_ENDPOINT, R2_RELAY_BUCKET, R2_RELAY_ACCESS_KEY_ID, and R2_RELAY_SECRET_ACCESS_KEY are all required',
                retryable=False,
            )
            return False
        try:
            await self._publish_identity()
        except Exception as exc:
            self._set_fatal_error('CONNECT_FAILED', f'R2 relay connect failed: {exc}', retryable=True)
            logger.error('r2 relay adapter connect failed server_id=%s: %s', self._relay_config.server_id, exc)
            return False
        logger.info(
            'published relay identity peer=%s discovery_conversation_id=%s discovery_thread_id=%s models=%s',
            self._relay_config.server_id,
            self._relay_config.discovery_conversation_id,
            self._relay_config.discovery_thread_id,
            len(self._relay_config.available_models),
        )
        self._abort_event = asyncio.Event()
        self._identity_heartbeat_task = asyncio.create_task(
            self._identity_heartbeat_loop(),
            name='r2-relay-identity-heartbeat',
        )
        self._poll_task = asyncio.create_task(self._poll_loop(), name='r2-relay-poll')
        logger.info(
            'started inbox polling task server_id=%s poll_interval_ms=%s backoff_max_ms=%s checkpoint_path=%s',
            self._relay_config.server_id,
            self._relay_config.poll_interval_ms,
            self._relay_config.backoff_max_ms,
            self._default_checkpoint_path,
        )
        self._mark_connected()
        return True

    async def disconnect(self) -> None:
        logger.info('stopping relay adapter server_id=%s', self._relay_config.server_id)
        self._abort_event.set()
        if self._identity_heartbeat_task is not None:
            self._identity_heartbeat_task.cancel()
            try:
                await self._identity_heartbeat_task
            except asyncio.CancelledError:
                logger.debug('relay identity heartbeat task cancelled server_id=%s', self._relay_config.server_id)
            finally:
                self._identity_heartbeat_task = None
        if self._poll_task is not None:
            self._poll_task.cancel()
            try:
                await self._poll_task
            except asyncio.CancelledError:
                logger.debug('relay polling task cancelled server_id=%s', self._relay_config.server_id)
            finally:
                self._poll_task = None
        self._mark_disconnected()
        logger.info('relay adapter disconnected server_id=%s', self._relay_config.server_id)

    async def send(
        self,
        chat_id: str,
        content: str,
        reply_to: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> SendResult:
        del reply_to
        if not self._relay_config.configured:
            logger.warning('relay send skipped: relay environment not configured chat_id=%s', chat_id)
            return SendResult(success=False, error='R2 relay is not configured in environment variables')
        metadata = dict(metadata or {})
        target_peer, target_conversation_id = parse_relay_target(chat_id)
        attachments = list(metadata.get('attachments') or []) or None
        auto_stream = '▉' in content and metadata.get('content_type', 'text') == 'text'
        clean_content = content.replace('▉', '').rstrip() if auto_stream else content
        auto_stream_id: str | None = None
        if auto_stream:
            auto_stream_id = new_stream_id(self.service)
            metadata['stream_id'] = auto_stream_id
            metadata['stream_seq'] = 1
            metadata['stream_state'] = 'partial'
        options = build_send_options(target_conversation_id, clean_content, attachments, metadata)
        logger.debug(
            'sending relay message target_peer=%s route=%s type=%s attachments=%s content_len=%s',
            target_peer,
            options.get('route'),
            options['content']['type'],
            len(attachments or []),
            len(clean_content.encode('utf-8')) if clean_content else 0,
        )
        try:
            result = await self.service.send_message(target_peer, options)
        except Exception as exc:
            logger.exception(
                'relay send failed target_peer=%s route=%s',
                target_peer,
                options.get('route'),
            )
            return SendResult(success=False, error=str(exc))
        if auto_stream and result.get('message_id'):
            self._stream_sessions[f'{chat_id}|{result.get("message_id")}'] = {
                'stream_id': auto_stream_id,
                'next_seq': 2,
                'route': options.get('route'),
                'target_peer': target_peer,
            }
        logger.debug(
            'relay send complete target_peer=%s message_id=%s key=%s',
            target_peer,
            result.get('message_id'),
            result.get('key'),
        )
        return SendResult(success=True, message_id=result.get('message_id'), raw_response=result)

    async def send_document(
        self,
        chat_id: str,
        file_path: str,
        caption: Optional[str] = None,
        file_name: Optional[str] = None,
        reply_to: Optional[str] = None,
        **kwargs,
    ) -> SendResult:
        del reply_to, kwargs
        return await self._send_uploaded_attachment(
            chat_id,
            file_path,
            caption=caption,
            file_name=file_name,
        )

    async def send_image_file(
        self,
        chat_id: str,
        image_path: str,
        caption: Optional[str] = None,
        reply_to: Optional[str] = None,
        **kwargs,
    ) -> SendResult:
        del reply_to, kwargs
        return await self._send_uploaded_attachment(
            chat_id,
            image_path,
            caption=caption,
        )

    async def send_voice(
        self,
        chat_id: str,
        audio_path: str,
        caption: Optional[str] = None,
        reply_to: Optional[str] = None,
        **kwargs,
    ) -> SendResult:
        del reply_to, kwargs
        return await self._send_uploaded_attachment(
            chat_id,
            audio_path,
            caption=caption,
        )

    async def send_video(
        self,
        chat_id: str,
        video_path: str,
        caption: Optional[str] = None,
        reply_to: Optional[str] = None,
        **kwargs,
    ) -> SendResult:
        del reply_to, kwargs
        return await self._send_uploaded_attachment(
            chat_id,
            video_path,
            caption=caption,
        )

    async def _send_uploaded_attachment(
        self,
        chat_id: str,
        file_path: str,
        caption: Optional[str] = None,
        file_name: Optional[str] = None,
    ) -> SendResult:
        if not self._relay_config.configured:
            logger.warning('relay attachment send skipped: relay environment not configured chat_id=%s', chat_id)
            return SendResult(success=False, error='R2 relay is not configured in environment variables')
        target_peer, target_conversation_id = parse_relay_target(chat_id)
        try:
            path = Path(file_path)
            data = path.read_bytes()
            resolved_name = file_name or path.name
            content_type = mimetypes.guess_type(resolved_name)[0] or 'application/octet-stream'
            message_id = f'msg-{int(time.time() * 1000)}'
            attachment = await self.service.store_attachment(
                recipient=target_peer,
                message_id=message_id,
                index=1,
                data=data,
                file_name=resolved_name,
                content_type=content_type,
            )
            options = build_send_options(target_conversation_id, caption or '', [attachment])
            logger.debug(
                'sending relay attachment target_peer=%s conversation_id=%s file_name=%s size=%s content_type=%s',
                target_peer,
                target_conversation_id,
                resolved_name,
                len(data),
                content_type,
            )
            result = await self.service.send_message(target_peer, options)
        except Exception as exc:
            logger.exception('relay attachment send failed target_peer=%s file_path=%s', target_peer, file_path)
            return SendResult(success=False, error=str(exc))
        logger.debug(
            'relay attachment send complete target_peer=%s message_id=%s key=%s',
            target_peer,
            result.get('message_id'),
            result.get('key'),
        )
        return SendResult(success=True, message_id=result.get('message_id'), raw_response=result)

    async def send_typing(self, chat_id: str, metadata=None) -> None:
        del chat_id, metadata
        return None

    async def edit_message(
        self,
        chat_id: str,
        message_id: str,
        content: str,
    ) -> SendResult:
        if not self._relay_config.configured:
            return SendResult(success=False, error='R2 relay is not configured in environment variables')

        stream_key = f'{chat_id}|{message_id}'
        state = self._stream_sessions.get(stream_key)
        if state is None:
            target_peer, target_conversation_id = parse_relay_target(chat_id)
            state = {
                'stream_id': new_stream_id(self.service),
                'next_seq': 1,
                'route': build_send_options(target_conversation_id, '').get('route'),
                'target_peer': target_peer,
            }
            self._stream_sessions[stream_key] = state

        next_seq = int(state['next_seq'])
        stream_state = 'partial' if '▉' in content else 'final'
        metadata = {
            'stream_id': state['stream_id'],
            'stream_seq': next_seq,
            'stream_state': stream_state,
        }
        if state.get('route'):
            metadata['route'] = state['route']

        result = await self.send(chat_id, content.replace('▉', '').rstrip(), metadata=metadata)
        if result.success:
            state['next_seq'] = next_seq + 1
            if stream_state == 'final':
                self._stream_sessions.pop(stream_key, None)
        return result

    async def get_chat_info(self, chat_id: str) -> Dict[str, Any]:
        return {'name': chat_id, 'type': 'dm', 'chat_id': chat_id}

    async def _poll_loop(self) -> None:
        logger.info(
            'entering relay poll loop server_id=%s poll_interval_ms=%s backoff_max_ms=%s',
            self._relay_config.server_id,
            self._relay_config.poll_interval_ms,
            self._relay_config.backoff_max_ms,
        )
        try:
            await self.service.poll_inbox(
                self._relay_config.server_id,
                self._handle_relay_message,
                poll_interval_ms=self._relay_config.poll_interval_ms,
                backoff_max_ms=self._relay_config.backoff_max_ms,
                abort_event=self._abort_event,
            )
        except asyncio.CancelledError:
            logger.debug('relay poll loop cancelled server_id=%s', self._relay_config.server_id)
            raise
        except Exception:
            logger.exception('relay poll loop failed server_id=%s', self._relay_config.server_id)
            raise
        finally:
            logger.info('relay poll loop exited server_id=%s', self._relay_config.server_id)

    async def _identity_heartbeat_loop(self) -> None:
        heartbeat_interval_s = IDENTITY_REFRESH_INTERVAL_MS / 1000
        logger.debug(
            'entering relay identity heartbeat loop server_id=%s interval_s=%s',
            self._relay_config.server_id,
            heartbeat_interval_s,
        )
        try:
            while not self._abort_event.is_set():
                await asyncio.sleep(heartbeat_interval_s)
                if self._abort_event.is_set():
                    break
                await self._publish_identity()
        except asyncio.CancelledError:
            logger.debug('relay identity heartbeat loop cancelled server_id=%s', self._relay_config.server_id)
            raise
        finally:
            logger.debug('relay identity heartbeat loop exited server_id=%s', self._relay_config.server_id)

    async def _handle_relay_message(self, msg: dict[str, Any], key: str) -> None:
        if not self._message_handler:
            logger.debug('dropping inbound relay message key=%s reason=no_handler', key)
            return
        peer = str(msg.get('from') or '')
        route = msg.get('route') if isinstance(msg.get('route'), dict) else {}
        conversation_id = route.get('conversation_id') or 'main'
        thread_id = route.get('instance_id') or conversation_id
        content = msg.get('content') if isinstance(msg.get('content'), dict) else {}
        attachments = content.get('attachments') if content.get('type') == 'text' else []
        logger.debug(
            'dispatching inbound relay message key=%s from=%s route=%s thread_id=%s attachments=%s',
            key,
            peer,
            route,
            thread_id,
            len(attachments or []),
        )
        source = self.build_source(
            chat_id=build_source_chat_id(peer, str(conversation_id) if conversation_id else None),
            user_id=peer,
            user_name=peer,
            chat_type='dm',
            thread_id=thread_id,
        )
        media_urls, media_types = await self._resolve_inbound_media(attachments or [])
        event = MessageEvent(
            text=format_inbound_text(msg),
            message_type=infer_message_type(attachments or []),
            source=source,
            raw_message={'relay_key': key, 'message': msg},
            message_id=msg.get('msg_id'),
            media_urls=media_urls,
            media_types=media_types,
            reply_to_message_id=content.get('target_msg_id') if content.get('type') == 'reaction' else None,
        )
        await self.handle_message(event)
        logger.debug('handled inbound relay message key=%s message_id=%s', key, msg.get('msg_id'))

    async def _resolve_inbound_media(self, attachments: list[dict[str, Any]]) -> tuple[list[str], list[str]]:
        media_urls: list[str] = []
        media_types: list[str] = []
        for attachment in attachments:
            key = attachment.get('key')
            if not key:
                logger.debug('skipping inbound attachment without key attachment=%s', attachment)
                continue
            fetched = None
            fetch_attachment = getattr(self.service, 'fetch_attachment', None)
            if callable(fetch_attachment):
                fetched = await fetch_attachment(
                    key,
                    file_name=attachment.get('file_name'),
                    content_type=attachment.get('content_type'),
                )
            logger.debug(
                'resolved inbound attachment key=%s fetched=%s file_path=%s content_type=%s',
                key,
                fetched is not None,
                (fetched or {}).get('file_path'),
                (fetched or {}).get('content_type') or attachment.get('content_type'),
            )
            media_urls.append((fetched or {}).get('file_path') or key)
            media_types.append(
                (fetched or {}).get('content_type')
                or attachment.get('content_type')
                or 'application/octet-stream'
            )
        return media_urls, media_types
