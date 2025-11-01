package com.example.exam.security;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

/**
 * Cấu hình DEV: cho phép tất cả các request (permitAll) để bạn phát triển nhanh.
 * Sau này có thể chuyển sang Basic Auth / JWT bằng cách thay đổi authorizeHttpRequests.
 */
@Configuration
public class SecurityConfig {

  @Bean
  public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http
        // CSRF thường tắt cho API stateless (JSON)
        .csrf(csrf -> csrf.disable())
        // CORS nếu bạn chạy UI ở cổng khác; có thể cấu hình chi tiết hơn nếu cần
        .cors(Customizer.withDefaults())
        // Stateless session cho REST API
        .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
        // Cho phép tất cả endpoint trong giai đoạn dev
        .authorizeHttpRequests(auth -> auth
            .requestMatchers("/**").permitAll()
            .anyRequest().permitAll()
        );
    return http.build();
  }
}