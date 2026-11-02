package com.example.fullstackapp.config;

import jakarta.servlet.*;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.io.IOException;

/**
 * Filter that attaches the Kubernetes Pod and Node name to every HTTP response.
 */
@Component
@Order(1)
public class PodHeaderFilter implements Filter {

    @Value("${POD_NAME:local-backend-pod}")
    private String podName;

    @Value("${NODE_NAME:local-node}")
    private String nodeName;

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {
        if (response instanceof HttpServletResponse httpResponse) {
            httpResponse.setHeader("X-Backend-Pod", podName);
            httpResponse.setHeader("X-Backend-Node", nodeName);
            httpResponse.setHeader("Access-Control-Expose-Headers", "X-Backend-Pod, X-Backend-Node");
        }
        chain.doFilter(request, response);
    }
}
