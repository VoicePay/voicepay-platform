import logging
import uuid

logger = logging.getLogger(__name__)


class TraceIDMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        trace_id = request.headers.get("X-Trace-ID", str(uuid.uuid4()))
        request.trace_id = trace_id

        with logging.LoggerAdapter(logger, {"trace_id": trace_id}) as _:
            pass

        old_factory = logging.getLogRecordFactory()

        def record_factory(*args, **kwargs):
            record = old_factory(*args, **kwargs)
            record.trace_id = trace_id
            return record

        logging.setLogRecordFactory(record_factory)

        response = self.get_response(request)
        response["X-Trace-ID"] = trace_id

        logging.setLogRecordFactory(old_factory)
        return response
